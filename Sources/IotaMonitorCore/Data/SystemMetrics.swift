//
//  SystemMetrics.swift
//  IotaMonitor
//
//  Local system measurements:
//   - bandwidth of the IOTA worker processes via nettop cumulative counters
//   - GPU utilization via ioreg (AGXAccelerator "Device Utilization %")
//   - worker CPU% via ps
//   - total system power via SMC key PSTR (Apple Silicon, unprivileged)
//

import Foundation
import IOKit

public struct NettopSample: Equatable {
    public let bytesIn: UInt64
    public let bytesOut: UInt64
}

public final class SystemMetrics {
    public static let shared = SystemMetrics()

    /// 与 IOTA worker 匹配的进程名（nettop 输出的 name.pid 形式里的 name）。
    public var processNames: [String] = ["main_pool", "IOTA Train at H"]
    private var lastNettop: NettopSample? = nil
    private var lastNettopAt: Date? = nil

    private let queue = DispatchQueue(label: "com.jyz.iota-monitor.sysmetrics")

    // MARK: - nettop

    /// 解析 `nettop -P -x -l 1` 的一行：`time name.pid bytes_in bytes_out ...`
    /// 进程名可能含空格（如 "IOTA Train at H.1730"），因此从行尾定位纯数字列。
    public static func parseNettopLine(_ line: String, matching names: [String]) -> NettopSample? {
        let cols = line.split(separator: " ", omittingEmptySubsequences: true)
        guard cols.count >= 4 else { return nil }

        // 从第 2 列起找到第一个"其后全是数字"的位置
        var numericStart = -1
        for i in 1..<cols.count {
            let tail = cols[i...]
            if tail.count >= 2 && tail.allSatisfy({ UInt64($0) != nil || Double($0) != nil }) {
                numericStart = i
                break
            }
        }
        guard numericStart >= 2 else { return nil } // name.pid + 至少 2 个数字列

        let procCol = cols[1..<numericStart].joined(separator: " ")
        guard let dotIdx = procCol.lastIndex(of: ".") else { return nil }
        let name = String(procCol[procCol.startIndex..<dotIdx])
        guard names.contains(where: { name.hasPrefix($0) }) else { return nil }

        let numbers = cols[numericStart...].compactMap { UInt64($0) }
        guard numbers.count >= 2 else { return nil }
        return NettopSample(bytesIn: numbers[0], bytesOut: numbers[1])
    }

    public static func aggregateNettop(output: String, names: [String]) -> NettopSample? {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var found = false
        for line in output.split(separator: "\n") {
            if let s = Self.parseNettopLine(String(line), matching: names) {
                totalIn += s.bytesIn
                totalOut += s.bytesOut
                found = true
            }
        }
        return found ? NettopSample(bytesIn: totalIn, bytesOut: totalOut) : nil
    }

    /// 两次调用做差分得到速率（bytes/s）。返回 nil 表示本机没有 worker 在跑或命令失败。
    public func sampleNetworkRates() -> (inPerSec: Double, outPerSec: Double)? {
        var result: (Double, Double)? = nil
        self.queue.sync {
            guard let output = self.runNettop(),
                  let current = Self.aggregateNettop(output: output, names: self.processNames) else {
                self.lastNettop = nil
                self.lastNettopAt = nil
                return
            }
            let now = Date()
            defer {
                self.lastNettop = current
                self.lastNettopAt = now
            }
            guard let prev = self.lastNettop, let prevAt = self.lastNettopAt else { return }
            let dt = now.timeIntervalSince(prevAt)
            guard dt > 0.5 else { return }
            let inRate = Double(current.bytesIn > prev.bytesIn ? current.bytesIn - prev.bytesIn : 0) / dt
            let outRate = Double(current.bytesOut > prev.bytesOut ? current.bytesOut - prev.bytesOut : 0) / dt
            result = (inRate, outRate)
        }
        return result
    }

    private func runNettop() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-x", "-l", "1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - GPU utilization

    /// 解析 ioreg 的 `"Device Utilization %"=30`
    public static func parseGPUUtilization(ioregOutput: String) -> Double? {
        guard let range = ioregOutput.range(of: #""Device Utilization %"=(\d+)"#, options: .regularExpression),
              let numberRange = ioregOutput[range].range(of: #"=\d+"#, options: .regularExpression) else { return nil }
        let raw = ioregOutput[numberRange].dropFirst()
        return Double(raw)
    }

    public func gpuUtilization() -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-d", "1", "-c", "AGXAccelerator"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return 0 }
        return Self.parseGPUUtilization(ioregOutput: out) ?? 0
    }

    // MARK: - worker CPU

    public func workerCpuUsage() -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "ps -Ao %cpu,comm | grep -iE 'main_pool|iota' | awk '{s+=$1} END {print s+0}'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(out.components(separatedBy: " ").first ?? "") else { return 0 }
        return value
    }

    // MARK: - SMC total power

    public func systemWatts() -> Double {
        if let value = SMC.shared.getValue("PSTR"), value > 0 {
            return value
        }
        return 0
    }
}

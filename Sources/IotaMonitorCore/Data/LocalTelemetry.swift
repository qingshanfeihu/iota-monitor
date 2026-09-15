//
//  LocalTelemetry.swift
//  IotaMonitor
//
//  Local data sources of the IOTA Train at Home app:
//   - port 8009 FastAPI telemetry (hotkeys/stats/counts/events)
//   - port 8010 control server GET /health (app alive)
//   - ~/Library/Logs/IOTA Train at Home/<today>-cli.log heartbeat lines
//

import Foundation

public final class LocalTelemetry {
    public static let shared = LocalTelemetry()

    public let logsDir: URL
    private let decoder = JSONDecoder()

    public init(logsDir: URL? = nil) {
        if let dir = logsDir {
            self.logsDir = dir
        } else {
            self.logsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/IOTA Train at Home")
        }
    }

    // MARK: - Port 8009 telemetry

    public func fetchHotkeys() -> [String]? {
        guard let data = try? self.localGet("http://127.0.0.1:8009/api/hotkeys"),
              let list = try? self.decoder.decode([String].self, from: data) else { return nil }
        return list
    }

    public func fetchStats(hotkey: String) -> TelemetryStats? {
        guard let data = try? self.localGet("http://127.0.0.1:8009/api/stats/\(hotkey)") else { return nil }
        return try? self.decoder.decode(TelemetryStats.self, from: data)
    }

    public func fetchCounts(hotkey: String) -> [TelemetryCountSnapshot]? {
        guard let data = try? self.localGet("http://127.0.0.1:8009/api/counts/\(hotkey)") else { return nil }
        return try? self.decoder.decode([TelemetryCountSnapshot].self, from: data)
    }

    public func fetchEvents(hotkey: String) -> [TelemetryEvent]? {
        guard let data = try? self.localGet("http://127.0.0.1:8009/api/events/\(hotkey)") else { return nil }
        return try? self.decoder.decode([TelemetryEvent].self, from: data)
    }

    /// 最新一个已完成阶段的名称与耗时，及最新内存占用。
    public func latestStage(hotkey: String) -> (name: String, duration: Double, mpsGB: Double)? {
        guard let events = self.fetchEvents(hotkey: hotkey) else { return nil }
        let ends = events.filter { $0.type == "end" }.sorted { ($0.time ?? 0) > ($1.time ?? 0) }
        guard let latest = ends.first, let name = latest.name else { return nil }
        let mps = events.last?.memory?.mps_allocated_gb ?? latest.memory?.mps_allocated_gb ?? 0
        return (name, latest.duration ?? 0, mps)
    }

    // MARK: - Port 8010 control server health (read-only GET)

    public func fetchHealth() -> ControlHealth? {
        guard let data = try? self.localGet("http://127.0.0.1:8010/health") else { return nil }
        return try? self.decoder.decode(ControlHealth.self, from: data)
    }

    public func isAppAlive() -> Bool {
        return self.fetchHealth() != nil
    }

    private func localGet(_ urlString: String) throws -> Data {
        guard let url = URL(string: urlString) else { throw FetchError.empty }
        return try HTTPFetcher.shared.get(url)
    }

    /// 权重文件名里直接提取 8 位短 hotkey 前缀（不依赖 8009 存活）。
    public func shortHotkeyFromWeights() -> String? {
        let weightsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/IOTA Train at Home/weights")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: weightsDir.path) else { return nil }
        for file in files {
            guard file.hasPrefix("current_model_weights_") else { continue }
            let rest = file.dropFirst("current_model_weights_".count)
            if let underscore = rest.firstIndex(of: "_") {
                let candidate = String(rest[rest.startIndex..<underscore])
                if candidate.count >= 8 {
                    return candidate
                }
            }
        }
        return nil
    }

    // MARK: - 完整 hotkey 解析

    /// 8009 /api/hotkeys 只返回 8 位短前缀；官方 API 需要完整 ss58 地址。
    /// 从当天 cli.log（节点注册表/节点列表）和权重文件名里找以该前缀开头的完整地址。
    public static let ss58Regex = try! NSRegularExpression(pattern: #"\b5[1-9A-HJ-NP-Za-km-z]{46,47}\b"#)

    public func expandHotkey(_ short: String) -> String? {
        guard short.count >= 8 else { return nil }

        // 1) 权重文件名 current_model_weights_<hotkey>_...
        let weightsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/IOTA Train at Home/weights")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: weightsDir.path) {
            for file in files where file.contains(short) {
                if let match = Self.firstSS58(in: file, prefix: short) {
                    return match
                }
            }
        }

        // 2) 当天日志尾部
        if let file = self.todayLogFile(),
           let handle = try? FileHandle(forReadingFrom: file) {
            defer { try? handle.close() }
            let size = Int64((try? handle.seekToEnd()) ?? 0)
            let start = max(0, size - 4_000_000)
            try? handle.seek(toOffset: UInt64(start))
            if let data = try? handle.read(upToCount: Int(min(4_000_000, size - start))),
               let text = String(data: data, encoding: .utf8) {
                if let match = Self.firstSS58(in: text, prefix: short) {
                    return match
                }
            }
        }
        return nil
    }

    static func firstSS58(in text: String, prefix: String) -> String? {
        let ns = text as NSString
        let matches = Self.ss58Regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let candidate = ns.substring(with: m.range(at: 0))
            if candidate.hasPrefix(prefix) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - cli.log heartbeat parsing

    /// 心跳响应字段会随 TAH 版本变化（早期含 layer/phase/status，
    /// 现在只剩 run_id + epoch），因此逐字段宽松解析：
    /// 行内须含 /miner/heartbeat 与 response，run_id 必需，其余缺失记 -1/空。
    public static func parseHeartbeatLine(_ line: String) -> HeartbeatState? {
        guard line.contains("/miner/heartbeat"), line.contains("response:") else { return nil }

        func capture(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges > 1 else { return nil }
            return ns.substring(with: m.range(at: 1))
        }

        guard let runId = capture(#"'run_id': '([^']+)'"#) else { return nil }
        let epoch = Int(capture(#"'epoch': (\d+)"#) ?? "") ?? -1
        let layer = Int(capture(#"'layer': (\d+)"#) ?? "") ?? -1
        let phase = capture(#"'phase': '([^']+)'"#) ?? ""
        let status = capture(#"'status': '([^']+)'"#) ?? ""
        return HeartbeatState(runId: runId, layer: layer, epoch: epoch, phase: phase, status: status, time: Date())
    }

    private func todayLogFile() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return self.logsDir.appendingPathComponent("\(formatter.string(from: Date()))-cli.log")
    }

    /// 读取当天日志的尾部若干 KB，解析出最新一次 heartbeat。
    public func latestHeartbeat(tailBytes: Int = 800_000) -> HeartbeatState? {
        guard let file = self.todayLogFile(),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let fileSize = Int64((try? handle.seekToEnd()) ?? 0)
        let readLen = Int64(tailBytes)
        let start = max(0, fileSize - readLen)
        try? handle.seek(toOffset: UInt64(start))
        guard let data = try? handle.read(upToCount: Int(min(readLen, fileSize - start))) else { return nil }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var state: HeartbeatState? = nil
        // 当天日志中的 heartbeat 每 ~10 秒一条，取最后一条
        for line in text.split(separator: "\n") {
            if let parsed = Self.parseHeartbeatLine(String(line)) {
                state = parsed
            }
        }
        return state
    }
}

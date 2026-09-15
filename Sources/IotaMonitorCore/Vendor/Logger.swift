//
//  Logger.swift
//  Adapted from exelban/stats (Kit/plugins/Logger.swift) — MIT License.
//  Simplified os_log based logger.
//

import Foundation
import os

public struct NextLog {
    public let category: String

    public init(category: String = "IotaMonitor") {
        self.category = category
    }

    public func copy(category: String) -> NextLog {
        return NextLog(category: category)
    }
}

private func emit(_ level: OSLogType, _ message: String, log: NextLog?) {
    let category = log?.category ?? "IotaMonitor"
    let osLog = OSLog(subsystem: "com.jyz.iota-monitor", category: category)
    os_log("%{public}@", log: osLog, type: level, message)
}

public func debug(_ message: String, log: NextLog? = nil) { emit(.debug, message, log: log) }
public func info(_ message: String, log: NextLog? = nil) { emit(.info, message, log: log) }
public func warning(_ message: String, log: NextLog? = nil) { emit(.default, message, log: log) }
public func error(_ message: String, log: NextLog? = nil) { emit(.error, message, log: log) }

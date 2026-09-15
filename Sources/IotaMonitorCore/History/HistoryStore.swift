//
//  HistoryStore.swift
//  IotaMonitor
//
//  SQLite persistence for history statistics.
//   samples(ts, watts, gpu, cpu, net_in, net_out)  — 5s raw samples, kept 14 days
//   daily(date, kwh, net_in_mb, net_out_mb, tokens, alpha)  — per-day aggregates
//   earnings(ts, alpha, status)  — payout event log from entitlements history
//

import Foundation
import SQLite3

/// 绑定文本时让 SQLite 自行拷贝内容（避免 Swift 字符串提前释放导致悬垂指针）。
let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

public struct DailyRecord: Codable, Equatable {
    public var date: String        // "yyyy-MM-dd" (local)
    public var kwh: Double
    public var netInMB: Double
    public var netOutMB: Double
    public var tokens: Double
    public var alpha: Double
}

public struct EarningRecord: Codable, Equatable {
    public var ts: Double
    public var alpha: Double
    public var status: String
}

public final class HistoryStore {
    public static let shared = HistoryStore()

    private var db: OpaquePointer? = nil
    private let queue = DispatchQueue(label: "com.jyz.iota-monitor.history")

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    public init(path: String? = nil) {
        let dbPath: String
        if let path = path {
            dbPath = path
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = support.appendingPathComponent("IotaMonitor", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbPath = dir.appendingPathComponent("history.sqlite").path
        }

        guard sqlite3_open(dbPath, &self.db) == SQLITE_OK else {
            error("failed to open history db at \(dbPath)")
            return
        }
        _ = self.exec("""
        CREATE TABLE IF NOT EXISTS samples (
            ts INTEGER PRIMARY KEY,
            watts REAL NOT NULL DEFAULT 0,
            gpu REAL NOT NULL DEFAULT 0,
            cpu REAL NOT NULL DEFAULT 0,
            net_in INTEGER NOT NULL DEFAULT 0,
            net_out INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS daily (
            date TEXT PRIMARY KEY,
            kwh REAL NOT NULL DEFAULT 0,
            net_in_mb REAL NOT NULL DEFAULT 0,
            net_out_mb REAL NOT NULL DEFAULT 0,
            tokens REAL NOT NULL DEFAULT 0,
            alpha REAL NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS earnings (
            ts REAL PRIMARY KEY,
            alpha REAL NOT NULL,
            status TEXT NOT NULL
        );
        """)
        self.pruneSamples()
    }

    deinit {
        sqlite3_close(self.db)
    }

    // MARK: - low level

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db = self.db else { return false }
        var err: UnsafeMutablePointer<CChar>? = nil
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let err = err {
                error("sqlite exec error: \(String(cString: err)) — \(sql.prefix(120))")
                sqlite3_free(err)
            }
            return false
        }
        return true
    }

    private func bindAndStep(_ sql: String, _ bind: (OpaquePointer) -> Void) -> Bool {
        guard let db = self.db else { return false }
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    // MARK: - samples

    public func insertSample(ts: Int, watts: Double, gpu: Double, cpu: Double, netIn: Int64, netOut: Int64) {
        self.queue.sync {
            guard watts > 0 || netIn > 0 || netOut > 0 else { return }
            _ = self.bindAndStep("INSERT OR REPLACE INTO samples(ts, watts, gpu, cpu, net_in, net_out) VALUES(?,?,?,?,?,?)") { stmt in
                sqlite3_bind_int64(stmt, 1, Int64(ts))
                sqlite3_bind_double(stmt, 2, watts)
                sqlite3_bind_double(stmt, 3, gpu)
                sqlite3_bind_double(stmt, 4, cpu)
                sqlite3_bind_int64(stmt, 5, netIn)
                sqlite3_bind_int64(stmt, 6, netOut)
            }
        }
    }

    /// 删除 14 天前的原始 samples（daily 汇总永久保留）。
    public func pruneSamples(olderThanDays: Int = 14) {
        let cutoff = Int(Date().timeIntervalSince1970) - olderThanDays * 86400
        self.queue.sync {
            _ = self.exec("DELETE FROM samples WHERE ts < \(cutoff)")
        }
    }

    // MARK: - daily

    /// 累加式更新某一天的汇总列（tokens/alpha 通常一次写入；kwh/net 为增量累加）。
    public func addToDaily(date: Date, dKWh: Double = 0, dNetInMB: Double = 0, dNetOutMB: Double = 0, setTokens: Double? = nil, setAlpha: Double? = nil) {
        let day = Self.dateString(from: date)
        self.queue.sync {
            // read current
            var current = DailyRecord(date: day, kwh: 0, netInMB: 0, netOutMB: 0, tokens: 0, alpha: 0)
            if let row = self.queryDaily(day) { current = row }
            let kwh = current.kwh + dKWh
            let netIn = current.netInMB + dNetInMB
            let netOut = current.netOutMB + dNetOutMB
            let tokens = setTokens ?? current.tokens
            let alpha = setAlpha ?? current.alpha
            _ = self.bindAndStep("INSERT OR REPLACE INTO daily(date, kwh, net_in_mb, net_out_mb, tokens, alpha) VALUES(?,?,?,?,?,?)") { stmt in
                sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 2, kwh)
                sqlite3_bind_double(stmt, 3, netIn)
                sqlite3_bind_double(stmt, 4, netOut)
                sqlite3_bind_double(stmt, 5, tokens)
                sqlite3_bind_double(stmt, 6, alpha)
            }
        }
    }

    private func queryDaily(_ day: String) -> DailyRecord? {
        guard let db = self.db else { return nil }
        var stmt: OpaquePointer? = nil
        let sql = "SELECT date, kwh, net_in_mb, net_out_mb, tokens, alpha FROM daily WHERE date = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, day, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return DailyRecord(
            date: day,
            kwh: sqlite3_column_double(statement, 1),
            netInMB: sqlite3_column_double(statement, 2),
            netOutMB: sqlite3_column_double(statement, 3),
            tokens: sqlite3_column_double(statement, 4),
            alpha: sqlite3_column_double(statement, 5)
        )
    }

    public func today() -> DailyRecord {
        return self.daily(since: nil, until: nil).first { $0.date == Self.dateString(from: Date()) }
            ?? DailyRecord(date: Self.dateString(from: Date()), kwh: 0, netInMB: 0, netOutMB: 0, tokens: 0, alpha: 0)
    }

    /// [since, until] 闭区间的日汇总，按日期升序。nil 表示不限制。
    public func daily(since: Date?, until: Date?) -> [DailyRecord] {
        var result: [DailyRecord] = []
        self.queue.sync {
            guard let db = self.db else { return }
            var sql = "SELECT date, kwh, net_in_mb, net_out_mb, tokens, alpha FROM daily"
            var conditions: [String] = []
            if let since = since { conditions.append("date >= '\(Self.dateString(from: since))'") }
            if let until = until { conditions.append("date <= '\(Self.dateString(from: until))'") }
            if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
            sql += " ORDER BY date ASC"

            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else { return }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                let c = sqlite3_column_text(statement, 0)
                result.append(DailyRecord(
                    date: c == nil ? "" : String(cString: c!),
                    kwh: sqlite3_column_double(statement, 1),
                    netInMB: sqlite3_column_double(statement, 2),
                    netOutMB: sqlite3_column_double(statement, 3),
                    tokens: sqlite3_column_double(statement, 4),
                    alpha: sqlite3_column_double(statement, 5)
                ))
            }
        }
        return result
    }

    // MARK: - earnings

    /// 用 entitlements history 全量覆盖（幂等）。
    public func syncEarnings(_ history: EntitlementHistory) {
        self.queue.sync {
            _ = self.exec("DELETE FROM earnings")
            let n = min(history.timestamps.count, history.alpha_amounts.count)
            guard n > 0 else { return }
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare_v2(self.db, "INSERT OR REPLACE INTO earnings(ts, alpha, status) VALUES(?,?,?)", -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else { return }
            defer { sqlite3_finalize(statement) }
            for i in 0..<n {
                let status = i < history.statuses.count ? history.statuses[i] : "settled"
                sqlite3_bind_double(statement, 1, history.timestamps[i])
                sqlite3_bind_double(statement, 2, history.alpha_amounts[i])
                sqlite3_bind_text(statement, 3, status, -1, SQLITE_TRANSIENT)
                if sqlite3_step(statement) != SQLITE_DONE { continue }
                sqlite3_reset(statement)
            }

            // 刷新 daily.alpha（同一天多笔累加）
            var byDay: [String: Double] = [:]
            for i in 0..<n {
                let day = Self.dateString(from: Date(timeIntervalSince1970: history.timestamps[i]))
                byDay[day, default: 0] += history.alpha_amounts[i]
            }
            for (day, alphaSum) in byDay {
                var current = self.queryDaily(day) ?? DailyRecord(date: day, kwh: 0, netInMB: 0, netOutMB: 0, tokens: 0, alpha: 0)
                current.alpha = alphaSum
                _ = self.bindAndStep("INSERT OR REPLACE INTO daily(date, kwh, net_in_mb, net_out_mb, tokens, alpha) VALUES(?,?,?,?,?,?)") { stmt in
                    sqlite3_bind_text(stmt, 1, day, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(stmt, 2, current.kwh)
                    sqlite3_bind_double(stmt, 3, current.netInMB)
                    sqlite3_bind_double(stmt, 4, current.netOutMB)
                    sqlite3_bind_double(stmt, 5, current.tokens)
                    sqlite3_bind_double(stmt, 6, current.alpha)
                }
            }
        }
    }

    public func earnings() -> [EarningRecord] {
        var result: [EarningRecord] = []
        self.queue.sync {
            guard let db = self.db else { return }
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare_v2(db, "SELECT ts, alpha, status FROM earnings ORDER BY ts ASC", -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else { return }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(EarningRecord(
                    ts: sqlite3_column_double(statement, 0),
                    alpha: sqlite3_column_double(statement, 1),
                    status: String(cString: sqlite3_column_text(statement, 2))
                ))
            }
        }
        return result
    }

    // MARK: - derived queries

    /// 某时间段内按小时聚合的功耗/流量（历史图表用）。
    public struct HourlyPoint {
        public let hourStart: Date
        public let wattsAvg: Double
        public let netInMB: Double
        public let netOutMB: Double
    }

    public func hourly(since: Date) -> [HourlyPoint] {
        var result: [HourlyPoint] = []
        self.queue.sync {
            guard let db = self.db else { return }
            let cutoff = Int(since.timeIntervalSince1970)
            let sql = """
            SELECT (ts/3600)*3600 AS h, AVG(watts), SUM(net_in), SUM(net_out)
            FROM samples WHERE ts >= \(cutoff) GROUP BY h ORDER BY h ASC
            """
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else { return }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(HourlyPoint(
                    hourStart: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0))),
                    wattsAvg: sqlite3_column_double(statement, 1),
                    netInMB: Double(sqlite3_column_int64(statement, 2)) / 1_000_000,
                    netOutMB: Double(sqlite3_column_int64(statement, 3)) / 1_000_000
                ))
            }
        }
        return result
    }

    /// 自给定时刻起累计的电量（kWh），按 samples 瓦特积分。
    public func energyKWh(since: Date) -> Double {
        guard let db = self.db else { return 0 }
        let cutoff = Int(since.timeIntervalSince1970)
        let sql = "SELECT ts, watts FROM samples WHERE ts >= \(cutoff) AND watts > 0 ORDER BY ts ASC"
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else { return 0 }
        defer { sqlite3_finalize(statement) }

        var lastTs: Double? = nil
        var wh: Double = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let ts = Double(sqlite3_column_int64(statement, 0))
            let w = sqlite3_column_double(statement, 1)
            if let prev = lastTs {
                wh += w * (ts - prev) / 3600.0
            }
            lastTs = ts
        }
        return wh / 1000.0
    }
}

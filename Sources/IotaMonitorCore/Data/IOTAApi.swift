//
//  IOTAApi.swift
//  IotaMonitor
//
//  Client for the Macrocosmos IOTA web API (backing the official dashboard).
//  URLSession first; falls back to `curl -4 --http1.1` because the host
//  intermittently stalls over IPv6/HTTP2.
//

import Foundation

public enum FetchError: Error, LocalizedError {
    case badStatus(Int)
    case empty

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .empty: return "empty response"
        }
    }
}

public struct HTTPFetcher {
    public static let shared = HTTPFetcher()
    public var useCurlFallback: Bool = true

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        return URLSession(configuration: config)
    }()

    public func get(_ url: URL) throws -> Data {
        var firstError: Error? = nil

        // attempt 1: URLSession
        var request = URLRequest(url: url)
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        let semaphore = DispatchSemaphore(value: 0)
        var received: Data? = nil
        var urlError: Error? = nil
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                urlError = error
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                urlError = FetchError.badStatus(http.statusCode)
            } else {
                received = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        if let data = received, urlError == nil {
            return try Self.maybeInflate(data)
        }
        firstError = urlError ?? FetchError.empty

        // attempt 2: curl -4 --http1.1
        if self.useCurlFallback {
            do {
                return try self.curlGet(url)
            } catch {
                throw firstError ?? error
            }
        }
        throw firstError ?? FetchError.empty
    }

    /// curl decodes gzip itself with --compressed.
    private func curlGet(_ url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-4", "--http1.1", "--compressed", "-sS", "--max-time", "20", url.absoluteString]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw FetchError.empty
        }
        return data
    }

    /// URLSession transparently decompresses gzip only when it set the header itself;
    /// when we set it manually we may receive raw gzip.
    static func maybeInflate(_ data: Data) throws -> Data {
        guard data.count > 2, data[0] == 0x1f, data[1] == 0x8b else { return data }
        return try data.gunzipped()
    }
}

extension Data {
    func gunzipped() throws -> Data {
        try (self as NSData).decompressed(using: .zlib) as Data
    }
}

public final class IOTAApi {
    public static let shared = IOTAApi()

    public let baseURL: URL
    public var hotkey: String
    public var runId: String

    public init(baseURL: URL = URL(string: "https://iota-web.api.macrocosmos.ai/mainnet")!,
                hotkey: String = "",
                runId: String = "") {
        self.baseURL = baseURL
        self.hotkey = hotkey
        self.runId = runId
    }

    private func getJSON(_ path: String) throws -> Data {
        guard let url = URL(string: "\(self.baseURL.absoluteString)\(path)") else {
            throw FetchError.empty
        }
        return try HTTPFetcher.shared.get(url)
    }

    // MARK: endpoints

    public func runs() throws -> [IotaRun] {
        try JSONDecoder().decode(RunsResponse.self, from: try self.getJSON("/runs")).runs
    }

    public func progress() throws -> TrainingProgress {
        try JSONDecoder().decode(TrainingProgress.self, from: try self.getJSON("/progress?run_id=\(self.runId)"))
    }

    public func phaseSnapshots() throws -> [PhaseSnapshot] {
        try JSONDecoder().decode(PhaseSnapshotsResponse.self, from: try self.getJSON("/phase_snapshots?run_id=\(self.runId)")).snapshots
    }

    public func miners() throws -> [MinerInfo] {
        try JSONDecoder().decode(MinersResponse.self, from: try self.getJSON("/miners?run_id=\(self.runId)")).miners
    }

    public func minerMetrics() throws -> MinerScores {
        try JSONDecoder().decode(MinerScores.self, from: try self.getJSON("/v1/epoch_miner_scores/runs/\(self.runId)/hotkeys/\(self.hotkey)/metrics?period=week"))
    }

    public func minerThroughput() throws -> MinerThroughputSeries {
        try JSONDecoder().decode(MinerThroughputSeries.self, from: try self.getJSON("/v1/epoch_miner_scores/runs/\(self.runId)/hotkeys/\(self.hotkey)/throughput?moving_average_window=0&period=week"))
    }

    public func entitlementTotals() throws -> EntitlementTotals {
        try JSONDecoder().decode(EntitlementTotals.self, from: try self.getJSON("/v1/entitlements/totals/hotkey/\(self.hotkey)"))
    }

    public func entitlementHistory() throws -> EntitlementHistory {
        try JSONDecoder().decode(EntitlementHistory.self, from: try self.getJSON("/v1/entitlements/history/hotkey/\(self.hotkey)"))
    }

    public func nextPayout() throws -> Date {
        let resp = try JSONDecoder().decode(NextPayout.self, from: try self.getJSON("/v1/entitlements/next_payout_timestamp"))
        return Date(timeIntervalSince1970: resp.next_payout_time)
    }

    public func runsOccupancy() throws -> RunsOccupancy {
        try JSONDecoder().decode(RunsOccupancy.self, from: try self.getJSON("/v1/runs_occupancy"))
    }
}

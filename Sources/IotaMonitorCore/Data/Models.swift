//
//  Models.swift
//  IotaMonitor
//
//  Codable models for the Macrocosmos IOTA (SN9) web API,
//  local TAH telemetry server and CoinGecko prices.
//

import Foundation

// MARK: - Official web API (iota-web.api.macrocosmos.ai/mainnet)

public struct RunsResponse: Codable {
    public let runs: [IotaRun]
}

public struct IotaRun: Codable {
    public let run_id: String
    public let name: String?
    public let state: String?
    public let is_default: Bool?
    public let metadata: RunMetadata?
    public let max_miners: Int?
}

public struct RunMetadata: Codable {
    public let dataset: DatasetMeta?
    public let n_splits: Int?
    public let model_name: String?
    public let model_size: String?
    public let description: String?
    public let is_miner_pool: Bool?
}

public struct DatasetMeta: Codable {
    public let mini_batch_size: Int?
    public let sequence_length: Int?
}

public struct TrainingProgress: Codable {
    public let loss: Double
    public let activation_count: Double?
    public let total_activations: Double?
    public let token_count: Double?
    public let total_tokens: Double?
}

public struct PhaseSnapshotsResponse: Codable {
    public let snapshots: [PhaseSnapshot]
}

public struct PhaseSnapshot: Codable {
    public let layer: Int
    public let epoch: Int
    public let phase: String?
    public let expected_activation_submissions: Int?
    public let activation_submission_count: Int?
    public let train_fraction: Double?
    public let upload_fraction: Double?
    public let merge_fraction: Double?
    public let phase_snapshot_ts: Double?
    public let phase_start_time: Double?
}

public struct MinersResponse: Codable {
    public let miners: [MinerInfo]
}

public struct MinerInfo: Codable {
    public let timestamp: Double?
    public let layer: Int
    public let miner_uid: Int?
    public let hotkey: String
    public let activation_count: Int?
    public let throughput: Double?
    public let incentive: Double?
    public let registration_time: Double?
    public let is_active: Bool
    public let run_id: String?
}

public struct MinerScores: Codable {
    public let run_id: String?
    public let hotkey: String?
    public let tokens_per_activation: Int?
    public let epochs: [Int]?
    public let token_counts: [Double]?
    public let act_contribution_percs: [Double]?
    public let activation_ranks: [Int]?
    public let num_hotkeys_in_epochs: [Int]?
    public let weight_uploaded: [Int]?
    public let uploaded_partition_percs: [Double]?
    public let timestamps: [Double]?
}

public struct MinerThroughputSeries: Codable {
    public let run_id: String?
    public let hotkey: String?
    public let tokens_per_activation: Int?
    public let epochs: [Int]?
    public let throughputs: [Double]?
    public let timestamps: [Double]?
}

public struct EntitlementTotals: Codable {
    public let total_amount_earned: Double
    public let total_amount_paid: Double
    public let total_amount_pending: Double
    public let total_amount_frozen: Double
    public let minimum_payout_amount: Double
}

public struct EntitlementHistory: Codable {
    public let alpha_amounts: [Double]
    public let timestamps: [Double]
    public let statuses: [String]

    public init(alpha_amounts: [Double], timestamps: [Double], statuses: [String]) {
        self.alpha_amounts = alpha_amounts
        self.timestamps = timestamps
        self.statuses = statuses
    }
}

public struct NextPayout: Codable {
    public let next_payout_time: Double
}

public struct RunsOccupancy: Codable {
    public let run_ids: [String]?
    public let max_miners: [Int]?
    public let active_miners: [Int]?
    public let slots_remaining: [Int]?
}

// MARK: - Prices (CoinGecko simple/price)

public struct CoinPrices {
    public let alphaUSD: Double?
    public let alphaCNY: Double?
    public let taoUSD: Double?
    public let taoCNY: Double?

    /// Custom decoding: {"iota-2":{"usd":6.29,"cny":44.8},"bittensor":{"usd":231.14}}
    public static func decode(from data: Data) -> CoinPrices {
        var alphaUSD: Double? = nil
        var alphaCNY: Double? = nil
        var taoUSD: Double? = nil
        var taoCNY: Double? = nil
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let alpha = json["iota-2"] as? [String: Any] {
                alphaUSD = alpha["usd"] as? Double
                alphaCNY = alpha["cny"] as? Double
            }
            if let tao = json["bittensor"] as? [String: Any] {
                taoUSD = tao["usd"] as? Double
                taoCNY = tao["cny"] as? Double
            }
        }
        return CoinPrices(alphaUSD: alphaUSD, alphaCNY: alphaCNY, taoUSD: taoUSD, taoCNY: taoCNY)
    }
}

// MARK: - Local TAH telemetry (127.0.0.1:8009)

public struct TelemetryStats: Codable {
    public let event_count: Int?
    public let count_log_count: Int?
    public let cumulative_counts: [String: Int]?
}

public struct TelemetryCountSnapshot: Codable {
    public let timestamp: Double
    public let total_events: Int?
    public let event_counts: [String: Int]?
    public let memory: TelemetryMemory?
}

public struct TelemetryMemory: Codable {
    public let mps_allocated_gb: Double?
    public let cpu_ram_gb: Double?
}

public struct TelemetryEvent: Codable {
    public let id: String?
    public let name: String?
    public let type: String?
    public let time: Double?
    public let duration: Double?
    public let metadata: [String: StringCodableBox]?
    public let memory: TelemetryMemory?
}

/// JSON values that may be string or number in event metadata.
public enum StringCodableBox: Codable {
    case string(String)
    case number(Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else {
            self = .string("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        }
    }

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        }
    }
}

public struct ControlHealth: Codable {
    public let ok: Bool?
    public let connected: Bool?
    public let sessionId: String?
    public let client: ControlClient?
}

public struct ControlClient: Codable {
    public let app: String?
    public let appVersion: String?
    public let pid: Int?
}

// MARK: - Log heartbeat

public struct HeartbeatState: Equatable {
    public var runId: String
    public var layer: Int
    public var epoch: Int
    public var phase: String
    public var status: String
    public var time: Date
}

// MARK: - System metrics

public struct LiveSystemMetrics {
    public var netInBytesPerSec: Double = 0
    public var netOutBytesPerSec: Double = 0
    public var gpuUtilization: Double = 0     // 0-100
    public var cpuUsage: Double = 0           // 0-100, worker processes
    public var watts: Double = 0              // SMC PSTR
    public var mpsMemoryGB: Double = 0
    public var appAlive: Bool = false
}

// MARK: - Aggregated snapshot shown in UI

public struct IotaSnapshot {
    // training state
    public var heartbeat: HeartbeatState? = nil
    public var appAlive: Bool = false
    public var appUptime: TimeInterval = 0
    public var progress: TrainingProgress? = nil
    public var phaseSnapshots: [PhaseSnapshot] = []
    public var currentStage: String = ""      // latest telemetry event name
    public var currentStageDuration: Double = 0
    public var mpsMemoryGB: Double = 0

    // miner scores
    public var latestEpoch: Int = 0
    public var latestTokensPerEpoch: Double = 0
    public var latestTokensPerHour: Double = 0
    public var rank: Int = 0
    public var totalMiners: Int = 0
    public var contribution: Double = 0

    // earnings
    public var totals: EntitlementTotals? = nil
    public var nextPayout: Date? = nil
    public var alphaToday: Double = 0
    public var earnings7d: [(Date, Double)] = []

    // live system
    public var live = LiveSystemMetrics()

    // today aggregates (from HistoryStore)
    public var todayTokens: Double = 0
    public var todayNetInMB: Double = 0
    public var todayNetOutMB: Double = 0
    public var todayKWh: Double = 0

    // prices
    public var prices: CoinPrices? = nil
}

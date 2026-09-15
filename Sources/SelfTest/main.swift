//
//  main.swift
//  SelfTest
//
//  本机无 Xcode（CLT 不含 XCTest），用独立执行器承载同样的断言。
//  swift run SelfTest
//

import Foundation
import IotaMonitorCore

var failures: [String] = []
var passed = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        passed += 1
    } else {
        failures.append(name)
        print("FAIL: \(name)")
    }
}

func checkEqual<T: Equatable>(_ name: String, _ a: T?, _ b: T) {
    check(name, a == b)
}

func checkNear(_ name: String, _ a: Double, _ b: Double, accuracy: Double = 0.0001) {
    check(name, abs(a - b) < accuracy)
}

// MARK: - nettop

do {
    let line = "14:58:55.758925 main_pool.3299    100694790    264203044    969   9017398    344684"
    let sample = SystemMetrics.parseNettopLine(line, matching: ["main_pool"])
    checkEqual("nettop.parse.bytesIn", sample?.bytesIn, 100_694_790)
    checkEqual("nettop.parse.bytesOut", sample?.bytesOut, 264_203_044)

    check("nettop.ignoreOthers", SystemMetrics.parseNettopLine("14:58:55.758919 Safari.999    12345    999    10   20   0", matching: ["main_pool"]) == nil)

    let electron = SystemMetrics.parseNettopLine("14:58:55.758919 IOTA Train at H.1730    39942    47984    101   2896    0", matching: ["IOTA Train at H"])
    checkEqual("nettop.electron.bytesIn", electron?.bytesIn, 39_942)

    let output = """
    14:58:55.758919 IOTA Train at H.1730    39942    47984    101   2896    0
    14:58:55.758925 main_pool.3299    100    200    1   2    0
    14:58:55.758926 main_pool.3400    50    60    1   2    0
    14:58:55.758926 WindowServer.88    999999    999999    9   9    0
    """
    let aggregated = SystemMetrics.aggregateNettop(output: output, names: ["main_pool", "IOTA Train at H"])
    checkEqual("nettop.aggregate.bytesIn", aggregated?.bytesIn, 39_942 + 150)
    checkEqual("nettop.aggregate.bytesOut", aggregated?.bytesOut, 47_984 + 260)
}

// MARK: - GPU

do {
    let ioreg = """
    "PerformanceStatistics" = {"In use system memory (driver)"=0,"Tiler Utilization %"=29,"Device Utilization %"=30,"SplitSceneCount"=0}
    "model" = "Apple M4"
    """
    checkEqual("gpu.parse", SystemMetrics.parseGPUUtilization(ioregOutput: ioreg), 30.0)
    check("gpu.missing", SystemMetrics.parseGPUUtilization(ioregOutput: "no stats here") == nil)
}

// MARK: - heartbeat

do {
    let line = "[2026-09-15 12:54:47.687] [info]  Successfully completed request to /miner/heartbeat?expected_phase=training; response: {'run_id': '4.12.16.2-tah', 'layer': 1, 'epoch': 64, 'phase': 'training', 'status': 'initializing'}"
    let state = LocalTelemetry.parseHeartbeatLine(line)
    checkEqual("heartbeat.runId", state?.runId, "4.12.16.2-tah")
    checkEqual("heartbeat.layer", state?.layer, 1)
    checkEqual("heartbeat.epoch", state?.epoch, 64)
    checkEqual("heartbeat.phase", state?.phase, "training")
    checkEqual("heartbeat.status", state?.status, "initializing")

    // 新版 TAH 心跳只剩 run_id + epoch，其余字段缺失不能误判为"未运行"
    let truncated = "/miner/heartbeat response: {'run_id': '4.12.16.2-tah', 'epoch': 65}"
    let state2 = LocalTelemetry.parseHeartbeatLine(truncated)
    checkEqual("heartbeat.truncated.runId", state2?.runId, "4.12.16.2-tah")
    checkEqual("heartbeat.truncated.epoch", state2?.epoch, 65)
    checkEqual("heartbeat.truncated.layer", state2?.layer, -1)
    checkEqual("heartbeat.truncated.phase", state2?.phase, "")

    check("heartbeat.noMatch", LocalTelemetry.parseHeartbeatLine("some random line") == nil)
    check("heartbeat.notHeartbeatLine", LocalTelemetry.parseHeartbeatLine("response: {'run_id': 'x', 'epoch': 1}") == nil)
}

// MARK: - models

do {
    let decoder = JSONDecoder()

    let totals = try decoder.decode(EntitlementTotals.self, from: """
    {"total_amount_earned": 9.44236282, "total_amount_paid": 9.05061304,
     "total_amount_pending": 0.39174978, "total_amount_frozen": 0,
     "minimum_payout_amount": 0.4}
    """.data(using: .utf8)!)
    checkNear("totals.earned", totals.total_amount_earned, 9.44236282)
    checkNear("totals.paid", totals.total_amount_paid, 9.05061304)
    checkNear("totals.min", totals.minimum_payout_amount, 0.4)

    let history = try decoder.decode(EntitlementHistory.self, from: """
    {"alpha_amounts": [1.369, 0, 0.392, 1.061],
     "timestamps": [1788825949, 1788912052, 1788912140, 1789085389],
     "statuses": ["settled", "settled", "pending", "settled"]}
    """.data(using: .utf8)!)
    checkEqual("history.count", history.alpha_amounts.count, 4)
    checkEqual("history.pending", history.statuses[2], "pending")

    let progress = try decoder.decode(TrainingProgress.self, from: """
    {"loss": 5.79340124, "activation_count": 185742, "total_activations": 15625000,
     "token_count": 594374400, "total_tokens": 50000000000}
    """.data(using: .utf8)!)
    checkNear("progress.loss", progress.loss, 5.79340124)
    checkEqual("progress.tokens", progress.token_count, 594_374_400.0)
    checkEqual("progress.total", progress.total_tokens, 50_000_000_000.0)

    let scores = try decoder.decode(MinerScores.self, from: """
    {"run_id": "4.12.16.2-tah", "hotkey": "5F1Q8nS8", "tokens_per_activation": 3200,
     "epochs": [63, 64], "token_counts": [528000, 499200],
     "act_contribution_percs": [0.0111, 0.0100], "activation_ranks": [24, 28],
     "num_hotkeys_in_epochs": [120, 120], "weight_uploaded": [1, 1],
     "uploaded_partition_percs": [1, 1], "timestamps": [1789430446, 1789436772]}
    """.data(using: .utf8)!)
    checkEqual("scores.rank", scores.activation_ranks?.last, 28)
    checkEqual("scores.miners", scores.num_hotkeys_in_epochs?.last, 120)

    let snapshots = try decoder.decode(PhaseSnapshotsResponse.self, from: """
    {"snapshots": [{"layer": 1, "epoch": 64, "phase": "training",
      "expected_activation_submissions": 104, "activation_submission_count": 42,
      "train_fraction": 0.42, "upload_fraction": 0.1, "merge_fraction": 0.0,
      "phase_snapshot_ts": 1789443000.5, "phase_start_time": 1789440000.0}]}
    """.data(using: .utf8)!).snapshots
    checkEqual("snapshots.layer", snapshots.first?.layer, 1)
    checkNear("snapshots.trainFraction", snapshots.first?.train_fraction ?? 0, 0.42, accuracy: 0.001)

    let prices = CoinPrices.decode(from: """
    {"bittensor":{"usd":231.14,"cny":1664.2},"iota-2":{"usd":6.29,"cny":45.3}}
    """.data(using: .utf8)!)
    checkEqual("prices.alphaUSD", prices.alphaUSD, 6.29)
    checkEqual("prices.taoUSD", prices.taoUSD, 231.14)
    checkEqual("prices.alphaCNY", prices.alphaCNY, 45.3)

    let events = try decoder.decode([TelemetryEvent].self, from: """
    [{"id": "abc", "name": "forward", "type": "end", "time": 1789443169.6,
      "duration": 2.31, "metadata": {"hotkey": "5F1Q", "layer": 1, "activation_id": 77},
      "memory": {"mps_allocated_gb": 2.92, "cpu_ram_gb": 0.58}}]
    """.data(using: .utf8)!)
    checkEqual("events.name", events.first?.name, "forward")
    checkNear("events.duration", events.first?.duration ?? 0, 2.31)
    checkNear("events.mps", events.first?.memory?.mps_allocated_gb ?? 0, 2.92)
    checkEqual("events.metadata.layer", events.first?.metadata?["layer"]?.stringValue, "1")

    let health = try decoder.decode(ControlHealth.self, from: """
    {"ok": true, "connected": true, "sessionId": "s1",
     "client": {"app": "macrocosmos-host", "appVersion": "3.7.0", "pid": 3400}}
    """.data(using: .utf8)!)
    checkEqual("health.version", health.client?.appVersion, "3.7.0")
    checkEqual("health.ok", health.ok, true)
} catch {
    failures.append("models.threw: \(error)")
}

// MARK: - HistoryStore

do {
    let store = HistoryStore(path: ":memory:")
    let now = Date()

    store.addToDaily(date: now, dKWh: 0.001, dNetInMB: 10, dNetOutMB: 20)
    store.addToDaily(date: now, dKWh: 0.002, dNetInMB: 5, dNetOutMB: 15)
    checkNear("store.kwh", store.today().kwh, 0.003)
    checkNear("store.netIn", store.today().netInMB, 15)
    checkNear("store.netOut", store.today().netOutMB, 35)

    store.addToDaily(date: now, setTokens: 100)
    store.addToDaily(date: now, setTokens: 250)
    checkNear("store.tokensOverwrite", store.today().tokens, 250)

    let day = Date(timeIntervalSinceNow: -3600)
    store.syncEarnings(EntitlementHistory(
        alpha_amounts: [1.5, 0.7],
        timestamps: [day.timeIntervalSince1970 - 86400, day.timeIntervalSince1970],
        statuses: ["settled", "settled"]
    ))
    checkEqual("store.earningsCount", store.earnings().count, 2)
    checkNear("store.alphaToday", store.today().alpha, 0.7)

    let start = Date(timeIntervalSinceNow: -3700)
    var ts = Int(start.timeIntervalSince1970)
    for _ in 0..<3600 {
        store.insertSample(ts: ts, watts: 10, gpu: 30, cpu: 20, netIn: 100, netOut: 200)
        ts += 1
    }
    checkNear("store.energyIntegration", store.energyKWh(since: start), 0.01, accuracy: 0.002)

    let hourlyStore = HistoryStore(path: ":memory:")
    let base = Int(Date(timeIntervalSinceNow: -7200).timeIntervalSince1970)
    hourlyStore.insertSample(ts: base, watts: 10, gpu: 0, cpu: 0, netIn: 1_000_000, netOut: 2_000_000)
    hourlyStore.insertSample(ts: base + 3600, watts: 20, gpu: 0, cpu: 0, netIn: 1_000_000, netOut: 2_000_000)
    let hourly = hourlyStore.hourly(since: Date(timeIntervalSince1970: TimeInterval(base - 10)))
    checkEqual("store.hourlyCount", hourly.count, 2)
    checkNear("store.hourlyWatts", hourly.first?.wattsAvg ?? -1, 10)
    checkNear("store.hourlyNetIn", hourly.first?.netInMB ?? -1, 1.0)
}

// MARK: - result

print("")
if failures.isEmpty {
    print("✅ \(passed) checks passed")
    exit(0)
} else {
    print("❌ \(failures.count) failed, \(passed) passed")
    failures.forEach { print("  - \($0)") }
    exit(1)
}

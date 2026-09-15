//
//  App.swift
//  IotaMonitor
//
//  Monitor: 轮询协调器（fast 5s / mid 60s / slow 300s），
//  驱动菜单栏组件与弹窗；AppDelegate 引导。
//

import Cocoa

public final class Monitor {
    public static let shared = Monitor()

    public let menuBar = MenuBar()
    private var widgets: [IotaWidget] = []

    private var popupWindow: PopupWindow? = nil
    private var popupView: IotaPopup? = nil

    private var fastTimer: Repeater? = nil
    private var midTimer: Repeater? = nil
    private var slowTimer: Repeater? = nil

    private(set) public var snapshot = IotaSnapshot()
    private let snapshotLock = NSLock()

    private var aliveSince: Date? = nil
    private var lastFastAt: Date? = nil
    private var earningsBaseline: Double = 0
    private var earningsBaselineDate: String = ""
    /// 8010 /health 最近一次结果（心跳格式变化或缺失时的存活兜底）
    private var healthAlive: Bool = false

    private var log = NextLog(category: "Monitor")

    // MARK: - lifecycle

    public func start() {
        self.setupWidgets()
        self.setupPopup()

        // 设置窗口控制器：注册 .toggleSettings 观察者（懒加载单例必须先触碰一次，
        // 否则弹窗"设置"按钮发通知时无人监听，表现为点了没反应）
        _ = SettingsWindowController.shared

        NotificationCenter.default.addObserver(self, selector: #selector(self.popupToggled), name: .togglePopup, object: nil)

        self.menuBar.enable()
        self.menuBar.recalculate()

        // 启动立即各跑一轮，再进入周期轮询
        DispatchQueue.global(qos: .utility).async { self.midCycle(force: true) }
        DispatchQueue.global(qos: .utility).async { self.slowCycle() }

        self.fastTimer = Repeater(seconds: 5) { [weak self] in self?.fastCycle() }
        self.midTimer = Repeater(seconds: 60) { [weak self] in self?.midCycle() }
        self.slowTimer = Repeater(seconds: 300) { [weak self] in self?.slowCycle() }
        self.fastTimer?.start()
        self.midTimer?.start()
        self.slowTimer?.start()

        info("monitor started", log: self.log)
    }

    public func refreshHotkey() {
        self.detectHotkey(force: true)
    }

    // MARK: - widgets & popup

    private func setupWidgets() {
        let list: [WidgetWrapper & IotaWidget] = [
            EarningsWidget(),
            ThroughputWidget(),
            NetWidget(),
            PowerWidget(),
            ChartWidget()
        ]
        // 默认只启用收益组件
        let defaultActive = "earnings"
        let stored = Store.shared.string(key: "IOTA_active_widgets", defaultValue: defaultActive)
        if stored.isEmpty {
            Store.shared.set(key: "IOTA_active_widgets", value: defaultActive)
        }
        for widget in list {
            self.menuBar.register(widget, id: widget.widgetId)
            self.widgets.append(widget)
        }
        self.menuBar.enable(id: "earnings")
    }

    private func setupPopup() {
        let view = IotaPopup(actions: .init(
            openIotaApp: {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.iota-train-at-home") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            },
            openDashboard: {
                if let url = URL(string: "https://iota.macrocosmos.ai/dashboard") {
                    NSWorkspace.shared.open(url)
                }
            },
            openSettings: {
                NotificationCenter.default.post(name: .toggleSettings, object: nil)
            },
            quit: {
                NSApp.terminate(nil)
            }
        ))
        self.popupView = view
        self.popupWindow = PopupWindow(view: view) { [weak self] state in
            if state {
                self?.pushToUI()
            }
        }
    }

    /// 状态栏图标点击：定位并显示/隐藏弹窗（移植自 stats Module.listenForPopupToggle）。
    @objc private func popupToggled(_ notification: Notification) {
        guard let popup = self.popupWindow,
              let buttonOrigin = notification.userInfo?["origin"] as? CGPoint,
              let buttonCenter = notification.userInfo?["center"] as? CGFloat else {
            return
        }

        DispatchQueue.main.async {
            let openedWindows = NSApplication.shared.windows.filter { $0 is NSPanel }
            openedWindows.forEach { $0.setIsVisible(false) }

            if popup.occlusionState.rawValue == 8192 || !popup.isVisible {
                NSApplication.shared.activate(ignoringOtherApps: true)

                popup.contentView?.invalidateIntrinsicContentSize()
                let windowCenter = popup.contentView!.intrinsicContentSize.width / 2
                var x = buttonOrigin.x - windowCenter + buttonCenter
                let y = buttonOrigin.y - popup.contentView!.intrinsicContentSize.height - 3

                let buttonPoint = NSPoint(x: buttonOrigin.x + buttonCenter, y: buttonOrigin.y)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
                    if x + popup.contentView!.intrinsicContentSize.width > screen.frame.maxX {
                        x = screen.frame.maxX - popup.contentView!.intrinsicContentSize.width - 3
                    }
                    if x < screen.frame.minX {
                        x = screen.frame.minX + 3
                    }
                }

                popup.setFrameOrigin(NSPoint(x: x, y: y))
                popup.setIsVisible(true)
                self.pushToUI()
            } else {
                popup.locked = false
                popup.setIsVisible(false)
            }
        }
    }

    // MARK: - hotkey / runId detection

    private func detectHotkey(force: Bool = false) {
        if !force {
            let stored = Store.shared.string(key: "hotkey", defaultValue: "")
            // 已有完整地址（>40 字符）则直接使用
            if stored.count > 40 {
                IOTAApi.shared.hotkey = stored
                return
            }
        }

        // 短前缀来源：8009 → 已存配置 → 权重文件名（IOTA App 未运行时 8009 不可用）
        var short: String? = LocalTelemetry.shared.fetchHotkeys()?.first
        if short == nil {
            let stored = Store.shared.string(key: "hotkey", defaultValue: "")
            short = stored.count >= 8 ? String(stored.prefix(8)) : LocalTelemetry.shared.shortHotkeyFromWeights()
        }
        guard let prefix = short else { return }

        // 本地短前缀扩展为完整 ss58（权重文件名 / 当天日志），失败则至少保留短前缀
        let full = prefix.count > 40 ? prefix : (LocalTelemetry.shared.expandHotkey(prefix) ?? prefix)
        IOTAApi.shared.hotkey = full
        Store.shared.set(key: "hotkey", value: full)
        // 只记前 8 位前缀：完整地址虽是链上公开信息，但没必要进统一日志
        info("detected hotkey \(full.prefix(8))…", log: self.log)
    }

    private func detectRunId(from heartbeat: HeartbeatState) {
        guard IOTAApi.shared.runId != heartbeat.runId else { return }
        IOTAApi.shared.runId = heartbeat.runId
        Store.shared.set(key: "run_id", value: heartbeat.runId)
        info("run id → \(heartbeat.runId)", log: self.log)
    }

    // MARK: - cycles

    /// fast 5s：系统指标 + heartbeat + 历史 samples 写入 + 今日累计。
    private func fastCycle() {
        let system = SystemMetrics.shared

        var live = self.snapshot.live
        let now = Date()

        if let rates = system.sampleNetworkRates() {
            live.netInBytesPerSec = rates.inPerSec
            live.netOutBytesPerSec = rates.outPerSec
        }
        live.gpuUtilization = system.gpuUtilization()
        live.cpuUsage = system.workerCpuUsage()
        live.watts = system.systemWatts()
        live.appAlive = self.snapshot.heartbeat != nil

        var dKWh = 0.0
        var dIn = 0.0
        var dOut = 0.0
        if let last = self.lastFastAt {
            let dt = now.timeIntervalSince(last)
            if live.appAlive {
                dKWh = live.watts * dt / 3600.0 / 1000.0
                dIn = live.netInBytesPerSec * dt / 1_000_000
                dOut = live.netOutBytesPerSec * dt / 1_000_000
                HistoryStore.shared.addToDaily(date: now, dKWh: dKWh, dNetInMB: dIn, dNetOutMB: dOut)
            }
        }
        self.lastFastAt = now

        if live.appAlive || live.watts > 0 {
            HistoryStore.shared.insertSample(
                ts: Int(now.timeIntervalSince1970),
                watts: live.watts,
                gpu: live.gpuUtilization,
                cpu: live.cpuUsage,
                netIn: Int64(live.netInBytesPerSec),
                netOut: Int64(live.netOutBytesPerSec)
            )
        }

        // heartbeat（本地日志，最即时的训练状态）；解析失败时用 8010 健康检查兜底
        if let hb = LocalTelemetry.shared.latestHeartbeat() {
            self.detectRunId(from: hb)
            self.mutate {
                $0.heartbeat = hb
                $0.appAlive = true
                if self.aliveSince == nil { self.aliveSince = Date() }
                $0.appUptime = Date().timeIntervalSince(self.aliveSince ?? Date())
            }
        } else {
            self.mutate { $0.heartbeat = nil; $0.appAlive = self.healthAlive }
            if !self.healthAlive { self.aliveSince = nil }
        }

        self.mutate { $0.live = live }
        let today = HistoryStore.shared.today()
        self.mutate {
            $0.todayKWh = today.kwh
            $0.todayNetInMB = today.netInMB
            $0.todayNetOutMB = today.netOutMB
        }

        self.pushToUI()
    }

    /// mid 60s：本地遥测（训练阶段事件、显存）+ 存活检查 + hotkey 探测。
    private func midCycle(force: Bool = false) {
        self.detectHotkey()

        // 8009 本地遥测以短 hotkey（/api/hotkeys 返回的 8 位前缀）为键，
        // 完整 ss58 地址查询会得到空数组（官方 API 才用完整地址）
        let fullKey = IOTAApi.shared.hotkey
        let localKey = LocalTelemetry.shared.fetchHotkeys()?.first ?? String(fullKey.prefix(8))
        if !localKey.isEmpty {
            if let stage = LocalTelemetry.shared.latestStage(hotkey: localKey) {
                self.mutate {
                    $0.currentStage = stage.name
                    $0.currentStageDuration = stage.duration
                    $0.mpsMemoryGB = stage.mpsGB
                }
            }
            if let health = LocalTelemetry.shared.fetchHealth() {
                self.healthAlive = health.ok ?? true
                self.mutate {
                    $0.appAlive = $0.heartbeat != nil || self.healthAlive
                }
            }
        }
        if force {
            self.pushToUI()
        }
    }

    /// slow 300s：官方 API（进度/收益/排名）+ 币价。
    private func slowCycle() {
        let t0 = Date()
        // 启动竞态保护：先确保 hotkey/runId 已探测（本地探测，很快）
        self.midCycle()
        if IOTAApi.shared.runId.isEmpty {
            IOTAApi.shared.runId = Store.shared.string(key: "run_id", defaultValue: "")
        }

        // 进度 & 阶段分数
        if !IOTAApi.shared.runId.isEmpty {
            do {
                let progress = try IOTAApi.shared.progress()
                self.mutate { $0.progress = progress }
            } catch { FileHandle.standardError.write("slowCycle progress: \(error)\n".data(using: .utf8)!) }
            do {
                let snapshots = try IOTAApi.shared.phaseSnapshots()
                self.mutate { $0.phaseSnapshots = snapshots }
            } catch { FileHandle.standardError.write("slowCycle phaseSnapshots: \(error)\n".data(using: .utf8)!) }
        }

        // 矿工成绩
        if !IOTAApi.shared.hotkey.isEmpty, !IOTAApi.shared.runId.isEmpty {
            do {
                let scores = try IOTAApi.shared.minerMetrics()
                let n = min(scores.epochs?.count ?? 0, scores.timestamps?.count ?? 0)
                if n > 0 {
                    let last = n - 1
                    let todayKey = Self.localDay(Date())
                    var tokensToday = 0.0
                    for i in 0..<n {
                        if let ts = scores.timestamps?[i], Self.localDay(Date(timeIntervalSince1970: ts)) == todayKey {
                            tokensToday += scores.token_counts?[i] ?? 0
                        }
                    }
                    let epochSeconds: Double = {
                        guard let stamps = scores.timestamps, stamps.count >= 2 else { return 6000 }
                        let diff = stamps[stamps.count-1] - stamps[stamps.count-2]
                        return diff > 0 ? diff : 6000
                    }()
                    let tokensPerEpoch = scores.token_counts?[last] ?? 0
                    self.mutate {
                        $0.latestEpoch = scores.epochs?[last] ?? 0
                        $0.latestTokensPerEpoch = tokensPerEpoch
                        $0.latestTokensPerHour = epochSeconds > 0 ? tokensPerEpoch / epochSeconds * 3600 : 0
                        $0.rank = scores.activation_ranks?[last] ?? 0
                        $0.totalMiners = scores.num_hotkeys_in_epochs?[last] ?? 0
                        $0.contribution = scores.act_contribution_percs?[last] ?? 0
                    }
                    HistoryStore.shared.addToDaily(date: Date(), setTokens: tokensToday)
                }
            } catch {
                FileHandle.standardError.write("slowCycle minerMetrics: \(error)\n".data(using: .utf8)!)
            }
        }

        // 收益
        if !IOTAApi.shared.hotkey.isEmpty {
            do {
                let totals = try IOTAApi.shared.entitlementTotals()
                self.applyEarnings(totals)
            } catch {
                FileHandle.standardError.write("slowCycle totals: \(error)\n".data(using: .utf8)!)
            }
            do {
                let history = try IOTAApi.shared.entitlementHistory()
                HistoryStore.shared.syncEarnings(history)
                let byDay = Self.groupEarningsByDay(history)
                self.mutate { s in
                    s.earnings7d = byDay.suffix(7).map { ($0.key, $0.value) }
                }
                // 当天已结算部分回拨基线，使 alphaToday 包含今天已到账金额
                let todayKey = Self.localDay(Date())
                let todaySettled = byDay.first { $0.key == todayKey }?.value ?? 0
                if let totals = self.snapshot.totals {
                    self.adjustBaseline(todaySettled: todaySettled, totals: totals)
                }
            } catch {
                FileHandle.standardError.write("slowCycle history: \(error)\n".data(using: .utf8)!)
            }
            do {
                let payout = try IOTAApi.shared.nextPayout()
                self.mutate { $0.nextPayout = payout }
            } catch {
                FileHandle.standardError.write("slowCycle payout: \(error)\n".data(using: .utf8)!)
            }
        }

        // 币价
        if let prices = PriceFetcher.shared.fetch() {
            self.mutate { $0.prices = prices }
        } else {
            FileHandle.standardError.write("slowCycle prices failed\n".data(using: .utf8)!)
        }

        // 今日 tokens 回填到快照
        let today = HistoryStore.shared.today()
        self.mutate { $0.todayTokens = today.tokens }

        let snapshotDebug = "slowCycle done: alphaToday=\(self.snapshot.alphaToday) prices=\(self.snapshot.prices?.alphaUSD ?? -1) currency=\(Store.shared.string(key: "currency", defaultValue: "USD"))\n"
        FileHandle.standardError.write(snapshotDebug.data(using: .utf8)!)
        self.pushToUI()
    }

    /// 今日收益 = 当前累计 - 当日基线（基线在每个本地新日期重置）。
    /// 基线创建后由 adjustBaseline(withTodaySettled:) 扣除当天已结算部分，
    /// 这样当天中途安装/重启也能正确显示"今日已结算 + 盘中新增"。
    private func applyEarnings(_ totals: EntitlementTotals) {
        let todayKey = Self.localDayKey(Date())
        let storedDate = Store.shared.string(key: "earnings_baseline_date", defaultValue: "")
        if storedDate != todayKey || self.earningsBaselineDate.isEmpty {
            self.earningsBaseline = totals.total_amount_earned
            self.earningsBaselineDate = todayKey
            Store.shared.set(key: "earnings_baseline", value: totals.total_amount_earned)
            Store.shared.set(key: "earnings_baseline_date", value: todayKey)
            Store.shared.set(key: "earnings_baseline_adjusted_date", value: "")
        } else if self.earningsBaseline == 0 {
            self.earningsBaseline = Store.shared.double(key: "earnings_baseline", defaultValue: totals.total_amount_earned)
        }
        self.recomputeAlphaToday(totals)
        // 黑匣子：把计算链路原值落盘，出问题可溯源
        let debug = "applyEarnings: earned=\(totals.total_amount_earned) baseline=\(self.earningsBaseline) baselineDate=\(self.earningsBaselineDate) storedDate=\(storedDate) hotkey=\(IOTAApi.shared.hotkey.suffix(6))\n"
        FileHandle.standardError.write(debug.data(using: .utf8)!)
        // daily.alpha 由 syncEarnings 按官方 payout 记录回填，这里不覆盖
    }

    /// 首次拿到当天 payout 记录后，把基线回拨到"当天零点"水平。
    private func adjustBaseline(todaySettled: Double, totals: EntitlementTotals) {
        let dbg = "adjustBaseline: todaySettled=\(todaySettled) baseline(before)=\(self.earningsBaseline) date=\(self.earningsBaselineDate)\n"
        FileHandle.standardError.write(dbg.data(using: .utf8)!)
        guard Self.localDayKey(Date()) == self.earningsBaselineDate,
              Store.shared.string(key: "earnings_baseline_adjusted_date", defaultValue: "") != self.earningsBaselineDate else {
            return
        }
        self.earningsBaseline = max(self.earningsBaseline - todaySettled, 0)
        Store.shared.set(key: "earnings_baseline", value: self.earningsBaseline)
        Store.shared.set(key: "earnings_baseline_adjusted_date", value: self.earningsBaselineDate)
        self.recomputeAlphaToday(totals)
    }

    private func recomputeAlphaToday(_ totals: EntitlementTotals) {
        // 保险丝：今日 = 累计 - 基线，数学上不可能超过累计总额；
        // 任何异常数据（超时残留/解析异常）都在这里被钳制
        let alphaToday = min(max(totals.total_amount_earned - self.earningsBaseline, 0), totals.total_amount_earned)
        self.mutate {
            $0.totals = totals
            $0.alphaToday = alphaToday
        }
        if alphaToday > 10 {
            // 日收益正常范围 0~3 IOTA，超 10 几乎必为异常，落盘留证
            Self.debugLog("SUSPICIOUS alphaToday=\(alphaToday) earned=\(totals.total_amount_earned) baseline=\(self.earningsBaseline) hotkey=\(IOTAApi.shared.hotkey)")
        }
    }

    /// 黑匣子：写入 Application Support，随 .app 启动也能留痕。
    static func debugLog(_ line: String) {
        let text = "\(Date().formatted()) \(line)\n"
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("IotaMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("debug.log")
        if let handle = FileHandle(forWritingAtPath: file.path) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? text.data(using: .utf8)?.write(to: file)
        }
        // 超过 512KB 截断，防无限增长
        if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, size > 512_000 {
            try? "…(truncated)\n".data(using: .utf8)?.write(to: file)
        }
    }

    // MARK: - helpers

    private static func localDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.startOfDay(for: date)
    }

    private static func localDayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func groupEarningsByDay(_ history: EntitlementHistory) -> [(key: Date, value: Double)] {
        var dict: [Date: Double] = [:]
        let n = min(history.timestamps.count, history.alpha_amounts.count)
        for i in 0..<n {
            let day = localDay(Date(timeIntervalSince1970: history.timestamps[i]))
            dict[day, default: 0] += history.alpha_amounts[i]
        }
        return dict.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
    }

    private func mutate(_ block: (inout IotaSnapshot) -> Void) {
        self.snapshotLock.lock()
        block(&self.snapshot)
        self.snapshotLock.unlock()
    }

    private func pushToUI() {
        let snapshot = self.snapshot
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.widgets.forEach { $0.update(snapshot) }
            self.popupView?.update(snapshot)
        }
    }
}

// MARK: - AppDelegate

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        Monitor.shared.start()
    }
}

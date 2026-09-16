//
//  PopupContent.swift
//  IotaMonitor
//
//  纵向卡片流弹窗：状态头 → 训练进度 → 今日 → 实时 → 收益 → 历史图表 → 底部操作。
//  全部使用 Auto Layout（NSStackView 自动排版 + 宽度/高度约束），
//  不对 arrangedSubview 手动设 frame（那会与 stack 布局引擎冲突，导致内容被压成 0 高）。
//

import Cocoa

// MARK: - 卡片容器

/// 圆角卡片：左上小标题 + 纵向内容栈，高度由内容自撑。
public final class CardView: NSView {
    public let titleLabel: NSTextField
    private let content: NSStackView

    public init(title: String) {
        self.titleLabel = NSTextField(labelWithString: title)
        self.titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        self.titleLabel.textColor = .secondaryLabelColor

        self.content = NSStackView()
        self.content.orientation = .vertical
        self.content.alignment = .leading
        self.content.spacing = 6

        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.10).cgColor

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.content.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.titleLabel)
        self.addSubview(self.content)

        NSLayoutConstraint.activate([
            self.titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 10),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            self.content.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 6),
            self.content.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            self.content.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
            self.content.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 加入一行内容：钉住宽度（与内容栈同宽），高度可选固定（行/条/图表）或由 intrinsic 决定。
    public func add(_ view: NSView, height: CGFloat? = nil) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.content.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: self.content.leadingAnchor).isActive = true
        view.widthAnchor.constraint(equalTo: self.content.widthAnchor).isActive = true
        if let h = height {
            view.heightAnchor.constraint(equalToConstant: h).isActive = true
        }
    }
}

// MARK: - 行与进度条

/// 左标签右数值的一行（纯约束：标签钉左缘、数值钉右缘，都垂直居中）。
/// 不要在 layout() 里手动摆放——首帧宽度未定时会算出负坐标，之后不再修正，
/// 表现为数值只剩最左 1-2 个字符。
public final class FieldRow: NSView {
    public let label: NSTextField
    public let value: NSTextField

    public init(labelText: String, valueText: String = "–") {
        self.label = NSTextField(labelWithString: labelText)
        self.label.font = NSFont.systemFont(ofSize: 12)
        self.label.textColor = .labelColor
        self.value = NSTextField(labelWithString: valueText)
        self.value.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.value.textColor = .labelColor
        self.value.alignment = .right

        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.value.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.label)
        self.addSubview(self.value)
        NSLayoutConstraint.activate([
            self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.value.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.value.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func set(_ text: String, color: NSColor? = nil) {
        self.value.stringValue = text
        self.value.textColor = color ?? .labelColor
    }
}

/// 横向进度条。
public final class ProgressBarView: NSView {
    private var progress: Double = 0

    public override func draw(_ dirtyRect: NSRect) {
        let radius = self.frame.height / 2
        let track = NSBezierPath(roundedRect: self.bounds, xRadius: radius, yRadius: radius)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.4).setFill()
        track.fill()

        let w = max(self.frame.width * CGFloat(min(max(self.progress, 0), 1)), radius)
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: self.frame.height), xRadius: radius, yRadius: radius)
        NSColor.controlAccentColor.setFill()
        fill.fill()
    }

    public func set(_ value: Double) {
        self.progress = value
        self.needsDisplay = true
    }
}

// MARK: - 主弹窗

public final class IotaPopup: PopupWrapper {
    private let popupWidth: CGFloat

    // 状态头
    private let statusTitle = NSTextField(labelWithString: "…")
    private let statusSubtitle = NSTextField(labelWithString: "")

    // 训练卡片
    private let lossRow = FieldRow(labelText: "loss")
    private let tokensProgress = ProgressBarView()
    private let tokensLabel = NSTextField(labelWithString: "")
    private let trainBarRow = FieldRow(labelText: "训练")
    private let trainBar = ProgressBarView()
    private let uploadBarRow = FieldRow(labelText: "上传")
    private let uploadBar = ProgressBarView()
    private let mergeBarRow = FieldRow(labelText: "合并")
    private let mergeBar = ProgressBarView()
    private let stageRow = FieldRow(labelText: "当前阶段")
    private let mpsRow = FieldRow(labelText: "显存 MPS")

    // 今日卡片
    private let todayTokensRow = FieldRow(labelText: "tokens")
    private let todayInRow = FieldRow(labelText: "下行流量")
    private let todayOutRow = FieldRow(labelText: "上行流量")
    private let todayEnergyRow = FieldRow(labelText: "电量")

    // 实时卡片
    private let liveGpuRow = FieldRow(labelText: "GPU")
    private let liveCpuRow = FieldRow(labelText: "CPU (worker)")
    private let liveWattsRow = FieldRow(labelText: "整机功率")
    private let netChart: NetworkChartView

    // 收益卡片
    private let earnTodayRow = FieldRow(labelText: "今日")
    private let earnTotalRow = FieldRow(labelText: "累计")
    private let earnPendingRow = FieldRow(labelText: "待付 / 冻结")
    private let payoutRow = FieldRow(labelText: "下次打款")
    private let rankRow = FieldRow(labelText: "全网排名")
    private let priceRow = FieldRow(labelText: "币价")

    // 历史卡片
    private let historyMetricPicker: NSPopUpButton
    private let historyRangePicker: NSPopUpButton
    private let historyModePicker: NSPopUpButton
    private let historyHint = NSTextField(labelWithString: "")
    private let historyChart: LineChartView

    // 底部
    private let actionsRow = NSStackView()

    // 缓存
    private var lastSnapshot: IotaSnapshot? = nil
    private let actions: PopupActions

    public struct PopupActions {
        public var openIotaApp: () -> Void
        public var openDashboard: () -> Void
        public var openSettings: () -> Void
        public var quit: () -> Void

        public init(openIotaApp: @escaping () -> Void, openDashboard: @escaping () -> Void,
                    openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
            self.openIotaApp = openIotaApp
            self.openDashboard = openDashboard
            self.openSettings = openSettings
            self.quit = quit
        }
    }

    public init(width: CGFloat = Constants.Popup.width, actions: PopupActions) {
        self.popupWidth = width
        self.actions = actions

        let chartWidth = width - 20
        self.netChart = NetworkChartView(
            frame: NSRect(x: 0, y: 0, width: chartWidth, height: 44),
            num: 120,
            minMax: false,
            outColor: .systemBlue,
            inColor: .systemRed,
            animation: false
        )

        self.historyMetricPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 110, height: 24), pullsDown: false)
        self.historyRangePicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 70, height: 24), pullsDown: false)
        self.historyModePicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 70, height: 24), pullsDown: false)
        self.historyChart = LineChartView(frame: NSRect(x: 0, y: 0, width: chartWidth, height: 84), num: 30, animation: false)
        self.historyChart.setColor(.systemBlue)

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        self.build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: build

    private func attach(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 4).isActive = true
        view.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -8).isActive = true
    }

    private func build() {
        // 状态头（无卡片背景）
        self.statusTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.statusSubtitle.font = NSFont.systemFont(ofSize: 11)
        self.statusSubtitle.textColor = .secondaryLabelColor
        self.tokensLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        self.tokensLabel.textColor = .secondaryLabelColor

        let statusStack = NSStackView()
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 2
        statusStack.addArrangedSubview(self.statusTitle)
        statusStack.addArrangedSubview(self.statusSubtitle)
        self.attach(statusStack)

        // 训练卡片
        let trainingCard = CardView(title: "训练进度")
        trainingCard.add(self.lossRow, height: 16)
        trainingCard.add(self.tokensProgress, height: 8)
        trainingCard.add(self.tokensLabel, height: 14)
        trainingCard.add(self.trainBarRow, height: 16)
        trainingCard.add(self.trainBar, height: 6)
        trainingCard.add(self.uploadBarRow, height: 16)
        trainingCard.add(self.uploadBar, height: 6)
        trainingCard.add(self.mergeBarRow, height: 16)
        trainingCard.add(self.mergeBar, height: 6)
        trainingCard.add(self.stageRow, height: 16)
        trainingCard.add(self.mpsRow, height: 16)
        self.attach(trainingCard)

        // 今日卡片
        let todayCard = CardView(title: "今日")
        todayCard.add(self.todayTokensRow, height: 16)
        todayCard.add(self.todayInRow, height: 16)
        todayCard.add(self.todayOutRow, height: 16)
        todayCard.add(self.todayEnergyRow, height: 16)
        self.attach(todayCard)

        // 实时卡片
        let liveCard = CardView(title: "实时")
        liveCard.add(self.liveGpuRow, height: 16)
        liveCard.add(self.liveCpuRow, height: 16)
        liveCard.add(self.liveWattsRow, height: 16)
        liveCard.add(self.netChart, height: 44)
        self.attach(liveCard)

        // 收益卡片
        let earnCard = CardView(title: "收益")
        earnCard.add(self.earnTodayRow, height: 16)
        earnCard.add(self.earnTotalRow, height: 16)
        earnCard.add(self.earnPendingRow, height: 16)
        earnCard.add(self.payoutRow, height: 16)
        earnCard.add(self.rankRow, height: 16)
        earnCard.add(self.priceRow, height: 16)
        self.attach(earnCard)

        // 历史卡片
        let historyCard = CardView(title: "历史")
        for metric in ["收益", "tokens", "下行流量", "上行流量", "功耗"] {
            self.historyMetricPicker.addItem(withTitle: metric)
        }
        for range in ["7 天", "30 天"] {
            self.historyRangePicker.addItem(withTitle: range)
        }
        for mode in ["每日", "累计"] {
            self.historyModePicker.addItem(withTitle: mode)
        }
        self.historyMetricPicker.selectItem(at: 0)
        self.historyRangePicker.selectItem(at: 0)
        self.historyModePicker.selectItem(at: 0)
        self.historyMetricPicker.controlSize = .small
        self.historyRangePicker.controlSize = .small
        self.historyModePicker.controlSize = .small
        self.historyHint.font = NSFont.systemFont(ofSize: 10)
        self.historyHint.textColor = .secondaryLabelColor
        self.historyMetricPicker.target = self
        self.historyMetricPicker.action = #selector(self.reloadHistory)
        self.historyRangePicker.target = self
        self.historyRangePicker.action = #selector(self.reloadHistory)
        self.historyModePicker.target = self
        self.historyModePicker.action = #selector(self.reloadHistory)

        let pickerRow = NSStackView()
        pickerRow.orientation = .horizontal
        pickerRow.spacing = 8
        pickerRow.addArrangedSubview(self.historyMetricPicker)
        pickerRow.addArrangedSubview(self.historyRangePicker)
        pickerRow.addArrangedSubview(self.historyModePicker)
        historyCard.add(pickerRow, height: 24)
        historyCard.add(self.historyHint, height: 12)
        historyCard.add(self.historyChart, height: 84)
        self.attach(historyCard)

        // 底部：版权信息（左）+ 紧凑文字按钮（右）
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let copyright = NSTextField(labelWithString: "IOTA Monitor v\(version) · © 2026 jiangyz")
        copyright.font = NSFont.systemFont(ofSize: 10)
        copyright.textColor = .tertiaryLabelColor

        self.actionsRow.orientation = .horizontal
        self.actionsRow.spacing = 12
        self.actionsRow.alignment = .centerY
        copyright.translatesAutoresizingMaskIntoConstraints = false
        self.actionsRow.addArrangedSubview(copyright)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.actionsRow.addArrangedSubview(spacer)
        let settingsButton = self.textButton(title: "设置", action: self.actions.openSettings)
        let quitButton = self.textButton(title: "退出", action: self.actions.quit)
        self.actionsRow.addArrangedSubview(settingsButton)
        self.actionsRow.addArrangedSubview(quitButton)
        self.actionsRow.setHuggingPriority(.defaultHigh, for: .horizontal)
        self.attach(self.actionsRow)

        self.spacing = 10

        self.relayout()
        self.reloadHistory()
    }

    /// 紧凑无边框文字按钮（用于底部操作行）。
    private func textButton(title: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 11)
        button.contentTintColor = .secondaryLabelColor
        button.focusRingType = .none
        let monitor = ActionMonitor(action: action)
        button.target = monitor
        button.action = #selector(ActionMonitor.fire)
        objc_setAssociatedObject(button, &ActionMonitor.assocKey, monitor, .OBJC_ASSOCIATION_RETAIN)
        return button
    }

    /// 让约束系统算出真实高度，再通知窗口调整。绝不手动摆放 arrangedSubview。
    private func relayout() {
        self.layoutSubtreeIfNeeded()
        let height = max(self.fittingSize.height, 120)
        let size = NSSize(width: self.popupWidth, height: height)
        self.setFrameSize(size)
        self.sizeCallback?(size)
    }

    // MARK: update

    public func update(_ snapshot: IotaSnapshot) {
        self.lastSnapshot = snapshot
        // 网速曲线后台持续采集（弹窗没开也要喂数据），
        // 否则每次打开只有打开后的几分钟，波形全是断点
        if snapshot.appAlive {
            self.netChart.addValue(upload: snapshot.live.netOutBytesPerSec, download: snapshot.live.netInBytesPerSec)
        }
        guard self.window?.isVisible ?? false else { return }
        self.render(snapshot)
    }

    public override func appear() {
        if let snapshot = self.lastSnapshot {
            self.render(snapshot)
        }
    }

    private func render(_ s: IotaSnapshot) {
        let currency = Store.shared.string(key: "currency", defaultValue: "USD")

        // 状态头（心跳字段可能缺失：phase 回退到官方阶段快照，layer 缺失则不显示）
        if s.appAlive {
            let hb = s.heartbeat
            let phase: String
            if let p = hb?.phase, !p.isEmpty {
                phase = p
            } else if let snapshotPhase = s.phaseSnapshots.first(where: { !($0.phase ?? "").isEmpty })?.phase {
                phase = snapshotPhase
            } else {
                phase = "运行中"
            }
            let layerText = (hb?.layer ?? -1) >= 0 ? " · Layer \(hb!.layer)" : ""
            let epochText = (hb?.epoch ?? -1) >= 0 ? " · Epoch \(hb!.epoch)" : ""
            self.statusTitle.stringValue = "\(phase == "training" || phase == "运行中" ? "◉" : "◎") \(phase)\(layerText)\(epochText)"
            self.statusTitle.textColor = (phase == "training" || phase == "运行中") ? NSColor.systemGreen : NSColor.systemOrange
            var subtitle = "run \(hb?.runId ?? IOTAApi.shared.runId) · IOTA App ✓"
            if s.appUptime > 60 {
                subtitle += " · 已运行 \(Self.durationText(s.appUptime))"
            }
            // 数据新鲜度：慢轮询数据滞后 15 分钟以上时明确提示
            if let updated = s.earningsUpdatedAt {
                let age = Date().timeIntervalSince(updated)
                if age > 3600 {
                    subtitle += " · 收益数据已 \(Int(age / 3600)) 小时未更新"
                } else if age > 900 {
                    subtitle += " · 收益数据已 \(Int(age / 60)) 分钟未更新"
                }
            } else {
                subtitle += " · 收益数据未获取"
            }
            self.statusSubtitle.stringValue = subtitle
        } else {
            self.statusTitle.stringValue = "◌ IOTA 未运行"
            self.statusTitle.textColor = NSColor.secondaryLabelColor
            self.statusSubtitle.stringValue = "等待 Train at Home 启动…"
        }

        // 训练卡片
        if let p = s.progress {
            self.lossRow.set(String(format: "%.4f", p.loss))
            let tokens = p.token_count ?? 0
            let total = p.total_tokens ?? 0
            if total > 0 {
                let fraction = tokens / total
                self.tokensProgress.set(fraction)
                self.tokensLabel.stringValue = "\(Self.compactNumber(tokens)) / \(Self.compactNumber(total)) tokens（\(String(format: "%.1f%%", fraction * 100))）"
            }
        } else {
            self.lossRow.set("–")
            self.tokensProgress.set(0)
            self.tokensLabel.stringValue = ""
        }
        let hbLayer = s.heartbeat?.layer ?? -1
        let myLayer = hbLayer >= 0 ? hbLayer : (s.phaseSnapshots.first?.layer ?? 1)
        if let layer1 = s.phaseSnapshots.first(where: { $0.layer == myLayer }) {
            self.trainBar.set(layer1.train_fraction ?? 0)
            self.uploadBar.set(layer1.upload_fraction ?? 0)
            self.mergeBar.set(layer1.merge_fraction ?? 0)
            self.trainBarRow.set(String(format: "%.0f%%", (layer1.train_fraction ?? 0) * 100))
            self.uploadBarRow.set(String(format: "%.0f%%", (layer1.upload_fraction ?? 0) * 100))
            self.mergeBarRow.set(String(format: "%.0f%%", (layer1.merge_fraction ?? 0) * 100))
        }
        if !s.currentStage.isEmpty {
            var stage = s.currentStage
            if s.currentStageDuration > 0 {
                stage += String(format: " · %.1fs", s.currentStageDuration)
            }
            self.stageRow.set(stage)
        } else {
            self.stageRow.set("–")
        }
        self.mpsRow.set(s.mpsMemoryGB > 0 ? String(format: "%.2f GB", s.mpsMemoryGB) : "–")

        // 今日卡片
        self.todayTokensRow.set(s.todayTokens > 0 ? Self.compactNumber(s.todayTokens) : "–")
        self.todayInRow.set(s.todayNetInMB > 0 ? String(format: "%.2f GB", s.todayNetInMB / 1000) : "–")
        self.todayOutRow.set(s.todayNetOutMB > 0 ? String(format: "%.2f GB", s.todayNetOutMB / 1000) : "–")
        if s.todayKWh > 0 {
            // 电量今天才几 Wh，用 kWh 会被 %.3f 舍成 0.000
            self.todayEnergyRow.set(s.todayKWh < 1
                ? String(format: "%.1f Wh", s.todayKWh * 1000)
                : String(format: "%.3f kWh", s.todayKWh))
        } else {
            self.todayEnergyRow.set("–")
        }

        // 实时卡片
        self.liveGpuRow.set(String(format: "%.0f%%", s.live.gpuUtilization))
        self.liveCpuRow.set(String(format: "%.0f%%", s.live.cpuUsage))
        self.liveWattsRow.set(s.live.watts > 0 ? String(format: "%.1f W", s.live.watts) : "–")

        // 收益卡片（SN9 的 alpha 代币即 IOTA，直接用代币名展示）
        let fiat = PriceFetcher.format(alpha: s.alphaToday, prices: s.prices, currency: currency)
        var todayText = String(format: "%.2f IOTA", s.alphaToday)
        if !fiat.isEmpty { todayText += "（\(fiat)）" }
        self.earnTodayRow.set(todayText, color: NSColor.systemGreen)
        if let t = s.totals {
            self.earnTotalRow.set(String(format: "%.2f IOTA（已付 %.2f）", t.total_amount_earned, t.total_amount_paid))
            self.earnPendingRow.set(String(format: "%.2f / %.2f IOTA", t.total_amount_pending, t.total_amount_frozen))
        }
        if let payout = s.nextPayout {
            let remain = payout.timeIntervalSinceNow
            self.payoutRow.set(remain > 0 ? "剩 \(Self.durationText(remain))" : "结算中…")
        } else {
            self.payoutRow.set("–")
        }
        if s.rank > 0 {
            self.rankRow.set(String(format: "%d / %d · 贡献 %.2f%%", s.rank, s.totalMiners, s.contribution * 100))
        } else {
            self.rankRow.set("–")
        }
        if let prices = s.prices,
           let alpha = currency == "CNY" ? (prices.alphaCNY ?? prices.alphaUSD) : prices.alphaUSD,
           let tao = currency == "CNY" ? (prices.taoCNY ?? prices.taoUSD) : prices.taoUSD {
            let symbol = currency == "CNY" ? "¥" : "$"
            self.priceRow.set("IOTA \(symbol)\(String(format: "%.2f", alpha)) · TAO \(symbol)\(String(format: "%.2f", tao))")
        } else {
            self.priceRow.set("–")
        }
        // 历史卡片已提供按日收益图表，这里不再重复展示

        self.relayout()
    }

    // MARK: history

    @objc private func reloadHistory() {
        let metric = self.historyMetricPicker.indexOfSelectedItem
        let days = self.historyRangePicker.indexOfSelectedItem == 0 ? 7 : 30
        let cumulative = self.historyModePicker.indexOfSelectedItem == 1
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        func dv(_ value: Double, at date: Date) -> DoubleValue {
            // 必须写入真实时间戳：DoubleValue 默认取创建时刻，
            // 同一轮创建的所有点时间相同 → x 轴刻度全部一样
            var point = DoubleValue(value)
            point.ts = date
            return point
        }
        func cumsum(_ pts: [DoubleValue]) -> [DoubleValue] {
            var acc = 0.0
            return pts.map { acc += $0.value; return dv(acc, at: $0.ts) }
        }

        var points: [DoubleValue] = []
        var suffix: String = ""
        let daily = HistoryStore.shared.daily(since: since, until: nil)

        switch metric {
        case 0:
            // 收益：跟随设置的货币自动折算（IOTA=原币数量，USD/CNY=当日数量×当前币价）
            let currency = Store.shared.string(key: "currency", defaultValue: "USD")
            let prices = Monitor.shared.snapshot.prices
            var rate = 1.0
            suffix = " IOTA"
            if currency == "USD", let p = prices?.alphaUSD, p > 0 {
                rate = p
                suffix = " $"
            } else if currency == "CNY" {
                let p = prices?.alphaCNY ?? (prices?.alphaUSD ?? 0) * Store.shared.double(key: "usd_cny_rate", defaultValue: 7.2)
                if p > 0 {
                    rate = p
                    suffix = " ¥"
                }
            }
            points = daily.map { dv($0.alpha * rate, at: Self.dayDate($0.date)) }
        case 1:
            points = daily.map { dv($0.tokens, at: Self.dayDate($0.date)) }
            suffix = " tok"
        case 2:
            points = daily.map { dv($0.netInMB, at: Self.dayDate($0.date)) }
            suffix = " MB"
        case 3:
            points = daily.map { dv($0.netOutMB, at: Self.dayDate($0.date)) }
            suffix = " MB"
        default:
            if cumulative {
                // 功耗的累计形态 = 累计电量 kWh（按天汇总积分）
                points = daily.map { dv($0.kwh, at: Self.dayDate($0.date)) }
                suffix = " kWh"
            } else {
                let hourly = HistoryStore.shared.hourly(since: since)
                points = hourly.map { dv($0.wattsAvg, at: $0.hourStart) }
                suffix = " W"
            }
        }

        if cumulative && metric != 4 {
            points = cumsum(points)
        }

        // x 轴铺满所选时间窗：reinit(n) 会把数据右对齐、左侧留空。
        // 之前 reinit(points.count) 让 7 天和 30 天画出来一模一样，切换"没反应"。
        let isHourly = (metric == 4 && !cumulative)
        let slotCount = isHourly ? days * 24 + 1 : days + 1
        self.historyChart.reinit(max(slotCount, points.count, 2))

        // 数据覆盖提示：窗口起点早于首条数据时说明留白原因
        if let firstDay = daily.map({ $0.date }).min(),
           let firstDate = Self.dayFormatter.date(from: firstDay),
           firstDate > Calendar.current.startOfDay(for: since) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            self.historyHint.stringValue = "数据自 \(formatter.string(from: firstDate)) 起，之前无记录（留白）"
        } else {
            self.historyHint.stringValue = ""
        }

        self.historyChart.setLegend(x: false, y: false)
        // stats 默认 tooltip 把数值 ×100（假定 0~1 百分比），必须重写为原值+单位
        let unit = suffix
        self.historyChart.setToolTipFunc { point in
            let v = abs(point.value) >= 1000
                ? String(format: "%.0f", point.value)
                : String(format: "%.2f", point.value)
            return "\(v)\(unit)"
        }
        self.historyChart.setSuffix(suffix)
        self.historyChart.setPoints(points)
        self.historyChart.needsDisplay = true
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func dayDate(_ string: String) -> Date {
        return Self.dayFormatter.date(from: string) ?? Date()
    }

    // MARK: helpers

    private static func compactNumber(_ value: Double) -> String {
        switch value {
        case 1_000_000_000...:
            return String(format: "%.2fB", value / 1_000_000_000)
        case 1_000_000..<1_000_000_000:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000..<1_000_000:
            return String(format: "%.1fk", value / 1_000)
        default:
            return String(format: "%.0f", value)
        }
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 24 {
            return "\(h / 24) 天 \(h % 24) 小时"
        }
        if h > 0 {
            return "\(h) 小时 \(m) 分"
        }
        return "\(m) 分"
    }
}

/// 按钮回调持有器。
private final class ActionMonitor: NSObject {
    static var assocKey: UInt8 = 0
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    @objc func fire() {
        self.action()
    }
}

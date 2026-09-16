//
//  IotaWidgets.swift
//  IotaMonitor
//
//  Menu bar widgets. All are NSView subclasses hosted inside the single
//  NSStatusItem button (stats' mechanism), width auto-adapts via setWidth().
//

import Cocoa

public protocol IotaWidget: AnyObject {
    var widgetId: String { get }
    var displayName: String { get }
    func update(_ snapshot: IotaSnapshot)
}

// MARK: - Base helpers

open class IotaBaseWidget: WidgetWrapper {
    public let font: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)

    public var valueColor: NSColor = .textColor
    public var secondaryColor: NSColor = .systemGreen

    public override func draw(_ dirtyRect: NSRect) {
        guard self.hasData else {
            self.drawUnavailable(dirtyRect)
            return
        }
        self.drawContent(dirtyRect)
    }

    open var hasData: Bool { true }
    open func drawContent(_ dirtyRect: NSRect) {}

    private func drawUnavailable(_ dirtyRect: NSRect) {
        let text = "–"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: self.font,
            .foregroundColor: NSColor.textColor.withAlphaComponent(0.4)
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (self.frame.width - size.width)/2, y: (self.frame.height - size.height)/2), withAttributes: attrs)
    }

    func drawText(_ parts: [(String, NSColor)], at point: NSPoint) -> CGFloat {
        var x = point.x
        for (text, color) in parts {
            let attrs: [NSAttributedString.Key: Any] = [.font: self.font, .foregroundColor: color]
            text.draw(at: NSPoint(x: x, y: (self.frame.height - text.heightOfString(usingFont: self.font))/2), withAttributes: attrs)
            x += text.widthOfString(usingFont: self.font)
        }
        return x - point.x
    }

    func width(of parts: [(String, NSColor)]) -> CGFloat {
        return parts.map { $0.0.widthOfString(usingFont: self.font) }.reduce(0, +)
    }
}

// MARK: - Earnings (default): α number + fiat + 24h sparkline

public final class EarningsWidget: IotaBaseWidget, IotaWidget {
    public let widgetId = "earnings"
    public let displayName = "今日收益"

    private var alphaToday: Double? = nil
    private var fiatText: String = ""
    private var history: [Double] = []
    private static let sparkWidth: CGFloat = 34

    public init() {
        super.init(
            title: "earnings",
            frame: NSRect(
                x: Constants.Widget.margin.x,
                y: Constants.Widget.margin.y,
                width: 60,
                height: Constants.Widget.height - (2*Constants.Widget.margin.y)
            )
        )
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ snapshot: IotaSnapshot) {
        if snapshot.appAlive {
            self.alphaToday = snapshot.alphaToday
            self.fiatText = PriceFetcher.format(
                alpha: snapshot.alphaToday,
                prices: snapshot.prices,
                currency: Store.shared.string(key: "currency", defaultValue: "USD")
            )
        } else {
            self.alphaToday = nil
            self.fiatText = ""
        }
        // 收益数据超过 15 分钟没成功刷新 → 数值后加"…"提示陈旧（API 停摆时不装作实时）
        if let updated = snapshot.earningsUpdatedAt, Date().timeIntervalSince(updated) > 900 {
            self.stale = true
        } else {
            self.stale = false
        }

        // 近 7 日收益 + 今日实时值
        self.history = snapshot.earnings7d.suffix(7).map { $0.1 }
        self.history.append(snapshot.alphaToday)

        let parts = self.textParts()
        let total = self.width(of: parts) + Self.sparkWidth + (Constants.Widget.margin.x*3)
        self.setWidth(total)
        self.redraw()
    }

    private var stale: Bool = false

    private func textParts() -> [(String, NSColor)] {
        guard let alpha = self.alphaToday else { return [("", .textColor)] }
        var parts: [(String, NSColor)] = [(String(format: "%.2f IOTA", alpha), self.valueColor)]
        if !self.fiatText.isEmpty {
            parts.append((" ", self.valueColor))
            parts.append((self.fiatText, self.secondaryColor))
        }
        if self.stale {
            parts.append((" …", NSColor.systemOrange))
        }
        return parts
    }

    public override var hasData: Bool { self.alphaToday != nil }

    public override func drawContent(_ dirtyRect: NSRect) {
        self.drawText(self.textParts(), at: NSPoint(x: Constants.Widget.margin.x, y: 0))
        let x0 = self.frame.width - Self.sparkWidth - Constants.Widget.margin.x
        self.drawSparkline(in: NSRect(x: x0, y: 3, width: Self.sparkWidth, height: self.frame.height - 6))
    }

    /// 手绘迷你折线（只描线不填充，避免渐变色块压住文字）。
    private func drawSparkline(in rect: NSRect) {
        guard self.history.count >= 2, rect.width > 4 else { return }
        let values = self.history
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 0.0001)
        let step = rect.width / CGFloat(values.count - 1)

        let path = NSBezierPath()
        for (i, v) in values.enumerated() {
            let x = rect.origin.x + CGFloat(i) * step
            let y = rect.origin.y + rect.height * CGFloat((v - minV) / span) * 0.8 + rect.height * 0.1
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.systemGreen.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }
}

// MARK: - Throughput

public final class ThroughputWidget: IotaBaseWidget, IotaWidget {
    public let widgetId = "throughput"
    public let displayName = "训练吞吐"

    private var tokensPerHour: Double? = nil

    public init() {
        super.init(
            title: "throughput",
            frame: NSRect(
                x: Constants.Widget.margin.x,
                y: Constants.Widget.margin.y,
                width: 52,
                height: Constants.Widget.height - (2*Constants.Widget.margin.y)
            )
        )
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ snapshot: IotaSnapshot) {
        let newValue = snapshot.appAlive && snapshot.latestTokensPerHour > 0 ? snapshot.latestTokensPerHour : nil
        guard newValue != self.tokensPerHour else { return }
        self.tokensPerHour = newValue
        let parts = self.textParts()
        self.setWidth(self.width(of: parts) + (Constants.Widget.margin.x*2))
        self.redraw()
    }

    private func textParts() -> [(String, NSColor)] {
        guard let v = self.tokensPerHour else { return [("", .textColor)] }
        let text: String
        if v >= 1_000_000 {
            text = String(format: "%.1fM/h", v / 1_000_000)
        } else if v >= 1_000 {
            text = String(format: "%.0fk/h", v / 1_000)
        } else {
            text = String(format: "%.0f/h", v)
        }
        return [(text, self.valueColor)]
    }

    public override var hasData: Bool { self.tokensPerHour != nil }

    public override func drawContent(_ dirtyRect: NSRect) {
        self.drawText(self.textParts(), at: NSPoint(x: Constants.Widget.margin.x, y: 0))
    }
}

// MARK: - Network

public final class NetWidget: IotaBaseWidget, IotaWidget {
    public let widgetId = "net"
    public let displayName = "网络速度"

    private var inRate: Double? = nil
    private var outRate: Double? = nil

    public init() {
        super.init(
            title: "net",
            frame: NSRect(
                x: Constants.Widget.margin.x,
                y: Constants.Widget.margin.y,
                width: 60,
                height: Constants.Widget.height - (2*Constants.Widget.margin.y)
            )
        )
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ snapshot: IotaSnapshot) {
        let newIn = snapshot.appAlive && snapshot.live.netInBytesPerSec > 1 ? snapshot.live.netInBytesPerSec : nil
        let newOut = snapshot.appAlive && snapshot.live.netOutBytesPerSec > 1 ? snapshot.live.netOutBytesPerSec : nil
        guard newIn != self.inRate || newOut != self.outRate else { return }
        self.inRate = newIn
        self.outRate = newOut
        let parts = self.textParts()
        self.setWidth(self.width(of: parts) + (Constants.Widget.margin.x*2))
        self.redraw()
    }

    private func textParts() -> [(String, NSColor)] {
        guard let out = self.outRate, let input = self.inRate else { return [("", .textColor)] }
        let up = Units(bytes: Int64(out)).getReadableSpeed()
        let down = Units(bytes: Int64(input)).getReadableSpeed()
        return [
            ("↑\(up)", NSColor.systemBlue),
            (" ", .textColor),
            ("↓\(down)", NSColor.systemRed)
        ]
    }

    public override var hasData: Bool { self.outRate != nil && self.inRate != nil }

    public override func drawContent(_ dirtyRect: NSRect) {
        self.drawText(self.textParts(), at: NSPoint(x: Constants.Widget.margin.x, y: 0))
    }
}

// MARK: - Power

public final class PowerWidget: IotaBaseWidget, IotaWidget {
    public let widgetId = "power"
    public let displayName = "整机功率"

    private var watts: Double? = nil

    public init() {
        super.init(
            title: "power",
            frame: NSRect(
                x: Constants.Widget.margin.x,
                y: Constants.Widget.margin.y,
                width: 40,
                height: Constants.Widget.height - (2*Constants.Widget.margin.y)
            )
        )
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ snapshot: IotaSnapshot) {
        let newWatts = snapshot.live.watts > 0 ? snapshot.live.watts : nil
        guard newWatts != self.watts else { return }
        self.watts = newWatts
        let parts = self.textParts()
        self.setWidth(self.width(of: parts) + (Constants.Widget.margin.x*2))
        self.redraw()
    }

    private func textParts() -> [(String, NSColor)] {
        guard let w = self.watts else { return [("", .textColor)] }
        return [(String(format: "%.0fW", w), self.valueColor)]
    }

    public override var hasData: Bool { self.watts != nil }

    public override func drawContent(_ dirtyRect: NSRect) {
        self.drawText(self.textParts(), at: NSPoint(x: Constants.Widget.margin.x, y: 0))
    }
}

// MARK: - Chart only (recent tokens/h line)

public final class ChartWidget: IotaBaseWidget, IotaWidget {
    public let widgetId = "chart"
    public let displayName = "图表"

    private var points: [DoubleValue] = []
    private let chart: LineChartView = LineChartView(
        frame: NSRect(x: 0, y: 0, width: 42, height: 16),
        num: 60,
        animation: false
    )

    public init() {
        super.init(
            title: "chart",
            frame: NSRect(
                x: Constants.Widget.margin.x,
                y: Constants.Widget.margin.y,
                width: 42,
                height: Constants.Widget.height - (2*Constants.Widget.margin.y)
            )
        )
        self.chart.setColor(.systemBlue)
        self.addSubview(self.chart)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ snapshot: IotaSnapshot) {
        guard snapshot.appAlive, snapshot.latestTokensPerHour > 0 else { return }
        self.points.append(DoubleValue(snapshot.latestTokensPerHour))
        if self.points.count > 60 { self.points.removeFirst(self.points.count - 60) }
        self.redraw()
    }

    public override var hasData: Bool { !self.points.isEmpty }

    public override func drawContent(_ dirtyRect: NSRect) {
        self.chart.setPoints(self.points)
    }
}

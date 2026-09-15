//
//  SettingsWindow.swift
//  IotaMonitor
//
//  设置窗口：分组表单（菜单栏组件 / 收益显示 / 数据源 / 电费 / 启动）。
//  复选框与分段控件即时生效，文本框在结束编辑时保存。
//

import Cocoa
import ServiceManagement

public final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow? = nil
    private var widgetCheckboxes: [String: NSButton] = [:]

    private let widgetOrder: [String] = ["earnings", "throughput", "net", "power", "chart"]
    private let widgetNames: [String: String] = [
        "earnings": "今日收益（IOTA + 折算 + 迷你曲线）",
        "throughput": "训练吞吐（tokens/h）",
        "net": "网络速度（↑↓）",
        "power": "整机功率（W）",
        "chart": "图表（吞吐折线）"
    ]

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(self.toggle), name: .toggleSettings, object: nil)
    }

    @objc private func toggle() {
        if let w = self.window, w.isVisible {
            w.orderOut(nil)
        } else {
            self.show()
        }
    }

    public func show() {
        if self.window == nil {
            self.window = self.buildWindow()
            self.window?.delegate = self
        }
        self.reload()
        self.window?.center()
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - build

    private func group(_ title: String, views: [NSView]) -> NSView {
        return SettingsGroup(title: title, views: views)
    }

    /// 圆角分组容器（与弹窗卡片同风格）。
    private final class SettingsGroup: NSView {
        init(title: String, views: [NSView]) {
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            titleLabel.textColor = .labelColor

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false
            self.wantsLayer = true
            self.layer?.cornerRadius = 8
            self.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.10).cgColor

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            stack.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(titleLabel)
            self.addSubview(stack)

            for view in views {
                view.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(view)
                view.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 10),
                titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 12),
                stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -12),
                stack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10)
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private func hint(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10.5)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// 标签 + 输入框（右侧）的一行。
    private func fieldRow(label: String, identifier: String, placeholder: String, width: CGFloat = 180) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 12)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        input.identifier = NSUserInterfaceItemIdentifier(rawValue: identifier)
        input.placeholderString = placeholder
        input.font = NSFont.systemFont(ofSize: 12)
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false
        input.widthAnchor.constraint(equalToConstant: width).isActive = true

        row.addArrangedSubview(labelField)
        row.addArrangedSubview(input)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    private func buildWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "IOTA Monitor 设置"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 400)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false

        // 1) 菜单栏组件
        var widgetViews: [NSView] = []
        for id in self.widgetOrder {
            let checkbox = NSButton(checkboxWithTitle: self.widgetNames[id] ?? id, target: self, action: #selector(self.widgetToggled(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier(rawValue: id)
            checkbox.font = NSFont.systemFont(ofSize: 12)
            self.widgetCheckboxes[id] = checkbox
            widgetViews.append(checkbox)
        }
        widgetViews.append(self.hint("可同时开启多个组件；变更立即生效。组件在菜单栏的顺序支持系统拖拽（按住 ⌘ 拖动）。"))
        content.addArrangedSubview(self.group("菜单栏组件", views: widgetViews))

        // 2) 收益显示
        let currencyRow = NSStackView()
        currencyRow.orientation = .horizontal
        currencyRow.spacing = 8
        currencyRow.alignment = .centerY
        currencyRow.addArrangedSubview(NSTextField(labelWithString: "收益显示货币"))
        let currencySeg = NSSegmentedControl(labels: ["IOTA", "USD", "CNY"], trackingMode: .selectOne, target: self, action: #selector(self.currencyChanged(_:)))
        currencySeg.identifier = NSUserInterfaceItemIdentifier(rawValue: "currency")
        currencyRow.addArrangedSubview(currencySeg)
        let currencyHint = NSTextField(labelWithString: "（IOTA=只看代币数量；法币价格来自 CoinGecko）")
        currencyHint.font = NSFont.systemFont(ofSize: 10.5)
        currencyHint.textColor = .secondaryLabelColor
        currencyRow.addArrangedSubview(currencyHint)
        let currencyStack = NSStackView()
        currencyStack.orientation = .vertical
        currencyStack.alignment = .leading
        currencyStack.spacing = 8
        currencyStack.addArrangedSubview(currencyRow)
        currencyStack.addArrangedSubview(self.fieldRow(label: "IOTA 手动币价（USD）", identifier: "price_override", placeholder: "留空 = 自动获取"))
        currencyStack.addArrangedSubview(self.fieldRow(label: "USD → CNY 汇率", identifier: "fx_rate", placeholder: "默认 7.2（CNY 折算兜底）"))
        content.addArrangedSubview(self.group("收益显示", views: [currencyStack]))

        // 3) 数据源
        let dataStack = NSStackView()
        dataStack.orientation = .vertical
        dataStack.alignment = .leading
        dataStack.spacing = 8
        dataStack.addArrangedSubview(self.fieldRow(label: "Hotkey", identifier: "hotkey", placeholder: "留空 = 自动探测（推荐）", width: 260))
        dataStack.addArrangedSubview(self.hint("监控通过本地遥测端口自动识别 hotkey，通常无需填写；仅当自动探测失败时手动填入完整地址。"))
        content.addArrangedSubview(self.group("数据源", views: [dataStack]))

        // 4) 电费
        let powerStack = NSStackView()
        powerStack.orientation = .vertical
        powerStack.alignment = .leading
        powerStack.spacing = 8
        powerStack.addArrangedSubview(self.fieldRow(label: "电价（¥/kWh）", identifier: "electricity", placeholder: "默认 0.55"))
        powerStack.addArrangedSubview(self.hint("用于收益净值参考；功率为 SMC 实测整机功耗。"))
        content.addArrangedSubview(self.group("电费", views: [powerStack]))

        // 5) 启动
        let launch = NSButton(checkboxWithTitle: "登录时自动启动 IOTA Monitor", target: self, action: #selector(self.launchToggled(_:)))
        launch.identifier = NSUserInterfaceItemIdentifier(rawValue: "launch")
        launch.font = NSFont.systemFont(ofSize: 12)
        let launchStack = NSStackView()
        launchStack.orientation = .vertical
        launchStack.alignment = .leading
        launchStack.spacing = 8
        launchStack.addArrangedSubview(launch)
        launchStack.addArrangedSubview(self.hint("需要应用位于 /Applications（已安装）。"))
        content.addArrangedSubview(self.group("启动", views: [launchStack]))

        // 底部关闭
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(self.close))
        closeButton.bezelStyle = .recessed
        let closeRow = NSStackView()
        closeRow.orientation = .horizontal
        closeRow.alignment = .centerX
        closeRow.addArrangedSubview(closeButton)
        content.addArrangedSubview(closeRow)

        let scrollView = NSScrollView()
        scrollView.documentView = content
        scrollView.hasVerticalScroller = true
       scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // 让内容随窗口伸缩
        content.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor).isActive = true
        content.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor).isActive = true
        content.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor).isActive = true
        content.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentView.bottomAnchor).isActive = true
        content.widthAnchor.constraint(greaterThanOrEqualToConstant: 428).isActive = true

        window.contentView = scrollView
        return window
    }

    // MARK: - load / save

    private func reload() {
        for (id, checkbox) in self.widgetCheckboxes {
            checkbox.state = Monitor.shared.menuBar.isActive(id: id) ? .on : .off
        }
        for (id, key) in [("hotkey", "hotkey"), ("fx_rate", "usd_cny_rate")] {
            if let field = self.textField(id) {
                if id == "hotkey" {
                    field.stringValue = Store.shared.string(key: key, defaultValue: "")
                } else {
                    let v = Store.shared.double(key: key, defaultValue: 7.2)
                    field.stringValue = String(v)
                }
            }
        }
        if let field = self.textField("price_override") {
            let v = Store.shared.double(key: "price_override_alpha", defaultValue: 0)
            field.stringValue = v > 0 ? String(v) : ""
        }
        if let field = self.textField("electricity") {
            let v = Store.shared.double(key: "electricity_price", defaultValue: 0.55)
            field.stringValue = String(v)
        }
        if let seg = self.segmented("currency") {
            let stored = Store.shared.string(key: "currency", defaultValue: "USD")
            seg.selectedSegment = stored == "IOTA" ? 0 : (stored == "CNY" ? 2 : 1)
        }
        if let launch = self.checkbox("launch") {
            launch.state = Self.isLaunchAtLoginEnabled() ? .on : .off
        }
    }

    private func textField(_ id: String) -> NSTextField? {
        guard let contentView = self.window?.contentView else { return nil }
        return self.findTextField(in: contentView, id: id)
    }

    private func findTextField(in view: NSView, id: String) -> NSTextField? {
        if let field = view as? NSTextField, field.identifier?.rawValue == id, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let found = self.findTextField(in: subview, id: id) {
                return found
            }
        }
        return nil
    }

    private func segmented(_ id: String) -> NSSegmentedControl? {
        guard let contentView = self.window?.contentView else { return nil }
        return self.find(in: contentView, id: id, type: NSSegmentedControl.self)
    }

    private func checkbox(_ id: String) -> NSButton? {
        guard let contentView = self.window?.contentView else { return nil }
        return self.find(in: contentView, id: id, type: NSButton.self)
    }

    private func find<T: NSView>(in view: NSView, id: String, type: T.Type) -> T? {
        if let matched = view as? T, view.identifier?.rawValue == id {
            return matched
        }
        for subview in view.subviews {
            if let found = self.find(in: subview, id: id, type: type) {
                return found
            }
        }
        return nil
    }

    // MARK: - actions（即时生效）

    @objc private func widgetToggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        Monitor.shared.menuBar.toggle(id: id)
    }

    @objc private func currencyChanged(_ sender: NSSegmentedControl) {
        let value = sender.selectedSegment == 0 ? "IOTA" : (sender.selectedSegment == 2 ? "CNY" : "USD")
        Store.shared.set(key: "currency", value: value)
    }

    @objc private func launchToggled(_ sender: NSButton) {
        Self.setLaunchAtLogin(sender.state == .on)
    }

    @objc private func close() {
        self.window?.orderOut(nil)
    }

    // 文本框结束编辑即保存
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let id = field.identifier?.rawValue else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        switch id {
        case "hotkey":
            if text.isEmpty {
                Store.shared.set(key: "hotkey", value: "")
                Monitor.shared.refreshHotkey()
            } else {
                Store.shared.set(key: "hotkey", value: text)
                Monitor.shared.refreshHotkey()
            }
        case "price_override":
            Store.shared.set(key: "price_override_alpha", value: Double(text) ?? 0)
        case "fx_rate":
            if let v = Double(text), v > 0 {
                Store.shared.set(key: "usd_cny_rate", value: v)
            }
        case "electricity":
            if let v = Double(text), v > 0 {
                Store.shared.set(key: "electricity_price", value: v)
            }
        default: break
        }
    }

    // MARK: - SMAppService

    public static func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return true
            default: return false
            }
        }
        return false
    }

    public static func setLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                warning("SMAppService \(enable ? "register" : "unregister") failed: \(error.localizedDescription)")
            }
        }
    }
}

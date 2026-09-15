//
//  Widget.swift
//  Adapted from exelban/stats (Kit/module/widget.swift) — MIT License.
//  Simplified single-module variant: one NSStatusItem hosts a row of widget views.
//

import Cocoa

public protocol widget_p: NSView {
    var widthHandler: (() -> Void)? { get set }
    var onClick: (() -> Void)? { get set }
    func settings() -> NSView
}

open class WidgetWrapper: NSView, widget_p {
    public var title: String
    public var widthHandler: (() -> Void)? = nil
    public var onClick: (() -> Void)? = nil
    public var shadowSize: CGSize
    internal var queue: DispatchQueue

    public init(title: String, frame: NSRect) {
        self.title = title
        self.shadowSize = frame.size
        self.queue = DispatchQueue(label: "com.jyz.iota-monitor.WidgetWrapper.\(title)")

        super.init(frame: frame)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setWidth(_ width: CGFloat) {
        var newWidth = width
        if width == 0 || width == 1 {
            newWidth = self.emptyView()
        }

        guard self.shadowSize.width != newWidth else { return }
        self.shadowSize.width = newWidth

        DispatchQueue.main.async {
            self.setFrameSize(NSSize(width: newWidth, height: self.frame.size.height))
            self.widthHandler?()
        }
    }

    private func emptyView() -> CGFloat {
        let size: CGFloat = 15
        let lineWidth = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
        let offset = lineWidth / 2
        let width: CGFloat = (Constants.Widget.margin.x*2) + size + (lineWidth*2)

        NSColor.textColor.set()

        var circle = NSBezierPath()
        circle = NSBezierPath(ovalIn: CGRect(x: Constants.Widget.margin.x+offset, y: 1+offset, width: size, height: size))
        circle.stroke()
        circle.lineWidth = lineWidth

        let line = NSBezierPath()
        line.move(to: NSPoint(x: 3, y: 3.5))
        line.line(to: NSPoint(x: 13.5, y: 14))
        line.lineWidth = lineWidth
        line.stroke()

        return width
    }

    public func redraw() {
        DispatchQueue.main.async { [weak self] in
            self?.needsDisplay = true
        }
    }

    open func settings() -> NSView { return NSView() }

    open override func mouseDown(with event: NSEvent) {
        if let f = self.onClick {
            f()
            return
        }
        super.mouseDown(with: event)
    }
}

/// Manages one NSStatusItem whose button hosts a container view (MenuBarView)
/// holding all enabled widgets side by side.
public class MenuBar {
    public var widgets: [widget_p] = []

    public func activeWidgetIds() -> [String] {
        return self.queue.sync { self._activeWidgets }
    }

    private var moduleName: String = "IOTA"
    private var menuBarItem: NSStatusItem? = nil
    private var queue: DispatchQueue
    private var _activeWidgets: [String] = []

    public var view: MenuBarView = MenuBarView()

    private var _active: Bool = false
    public var active: Bool {
        get { self.queue.sync { self._active } }
        set { self.queue.sync { self._active = newValue } }
    }

    init() {
        self.queue = DispatchQueue(label: "com.jyz.iota-monitor.MenuBar")
        self._activeWidgets = (Store.shared.string(key: "\(self.moduleName)_active_widgets", defaultValue: "") as String)
            .split(separator: ",").map { String($0) }
        self.view.identifier = NSUserInterfaceItemIdentifier(rawValue: moduleName)
    }

    // MARK: - widget registry

    public func register(_ widget: widget_p, id: String) {
        widget.identifier = NSUserInterfaceItemIdentifier(rawValue: id)
        widget.widthHandler = { [weak self] in
            DispatchQueue.main.async { self?.recalculate() }
        }
        self.widgets.append(widget)
        if self.isActive(id: id), let view = self.widgets.first(where: { $0.identifier?.rawValue == id }) {
            self.view.addWidget(view)
        }
    }

    public func isActive(id: String) -> Bool {
        return self._activeWidgets.contains(id)
    }

    public func enable(id: String) {
        guard !self.isActive(id: id) else { return }
        self._activeWidgets.append(id)
        Store.shared.set(key: "\(self.moduleName)_active_widgets", value: self._activeWidgets.joined(separator: ","))
        if let view = self.widgets.first(where: { $0.identifier?.rawValue == id }) {
            self.view.addWidget(view)
            NotificationCenter.default.post(name: .widgetRearrange, object: nil, userInfo: ["module": self.moduleName])
        }
        self.recalculate()
    }

    public func disable(id: String) {
        guard self.isActive(id: id) else { return }
        self._activeWidgets.removeAll { $0 == id }
        Store.shared.set(key: "\(self.moduleName)_active_widgets", value: self._activeWidgets.joined(separator: ","))
        self.view.removeWidget(id: id)
        self.recalculate()
    }

    public func toggle(id: String) {
        if self.isActive(id: id) {
            self.disable(id: id)
        } else {
            self.enable(id: id)
        }
    }

    private func sortedIds() -> [String] {
        var list: [String: Int] = [:]
        self._activeWidgets.forEach { id in
            list[id] = Store.shared.int(key: "iota_widget_\(id)_position", defaultValue: 0)
        }
        var sorted = list.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }.map { $0.key }
        // stable ordering also respects registry order for equal positions
        let registryOrder = self.widgets.compactMap { $0.identifier?.rawValue }
        sorted.sort { a, b in
            let pa = list[a] ?? 0, pb = list[b] ?? 0
            if pa != pb { return pa < pb }
            let ia = registryOrder.firstIndex(of: a) ?? 0
            let ib = registryOrder.firstIndex(of: b) ?? 0
            return ia < ib
        }
        return sorted
    }

    // MARK: - status item

    public func enable() {
        self.active = true
        DispatchQueue.main.async(execute: {
            guard self.menuBarItem == nil else { return }
            restoreNSStatusItemPosition(id: self.moduleName)
            self.menuBarItem = NSStatusBar.system.statusItem(withLength: 0)
            DispatchQueue.main.async(execute: {
                self.menuBarItem?.autosaveName = self.moduleName
            })
            self.menuBarItem?.isVisible = true

            self.menuBarItem?.button?.addSubview(self.view)
            self.menuBarItem?.button?.image = NSImage()
            self.menuBarItem?.button?.toolTip = "IOTA Train at Home"
            self.menuBarItem?.button?.target = self
            self.menuBarItem?.button?.action = #selector(self.togglePopup)
            self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])

            self.recalculate()
        })
    }

    public func disable() {
        self.active = false
        DispatchQueue.main.async(execute: {
            guard let item = self.menuBarItem else { return }
            saveNSStatusItemPosition(id: self.moduleName)
            NSStatusBar.system.removeStatusItem(item)
            self.menuBarItem = nil
        })
    }

    public func recalculate() {
        guard self.active, let item = self.menuBarItem else { return }

        let ids = self.sortedIds()
        var w: CGFloat = Constants.Widget.spacing * 2
        ids.forEach { id in
            if let view = self.widgets.first(where: { $0.identifier?.rawValue == id }) {
                w += view.frame.width + Constants.Widget.spacing
            }
        }
        if ids.isEmpty { w = CGFloat(30) }

        item.length = w
        self.view.setFrameOrigin(NSPoint(x: 0, y: 0))
        self.view.setFrameSize(NSSize(width: w, height: Constants.Widget.height))

        var x: CGFloat = Constants.Widget.spacing
        ids.forEach { id in
            if let view = self.widgets.first(where: { $0.identifier?.rawValue == id }) {
                view.setFrameOrigin(NSPoint(x: x, y: view.frame.origin.y))
                x = view.frame.origin.x + view.frame.width + Constants.Widget.spacing
            }
        }
    }

    @objc private func togglePopup() {
        if let item = self.menuBarItem, let window = item.button?.window {
            NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
                "module": self.moduleName,
                "origin": window.frame.origin,
                "center": window.frame.width/2
            ])
        }
    }
}

public class MenuBarView: NSView {
    init() {
        super.init(frame: NSRect.zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func addWidget(_ view: NSView) {
        self.addSubview(view)
    }

    public func removeWidget(id: String) {
        if let view = self.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier(id) }) {
            view.removeFromSuperview()
        }
    }
}

// MARK: - Status item position persistence (from stats Kit/helpers.swift)

func saveNSStatusItemPosition(id: String) {
    let position = Store.shared.int(key: "NSStatusItem Preferred Position \(id)", defaultValue: -1)
    if position != -1 {
        Store.shared.set(key: "NSStatusItem Restore Position \(id)", value: position)
    }
}

func restoreNSStatusItemPosition(id: String) {
    let prevPosition = Store.shared.int(key: "NSStatusItem Restore Position \(id)", defaultValue: -1)
    if prevPosition != -1 {
        Store.shared.set(key: "NSStatusItem Preferred Position \(id)", value: prevPosition)
        Store.shared.remove("NSStatusItem Restore Position \(id)")
    }
}

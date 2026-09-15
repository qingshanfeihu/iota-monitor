//
//  Popup.swift
//  Adapted from exelban/stats (Kit/module/popup.swift) — MIT License.
//  Borderless-looking popup window with vibrancy, auto-close on focus loss,
//  pin-on-drag behaviour, and render-only-when-visible cache.
//  Header bar removed for this app: actions live in the popup's bottom row.
//

import Cocoa

public final class PopupCache<T> {
    public var value: T?
    public var initialized: Bool = false

    public init() {}

    public func apply(_ value: T, visible: Bool, render: (T) -> Void) {
        self.value = value
        if visible || !self.initialized {
            render(value)
            self.initialized = true
        }
    }

    public func replay(render: (T) -> Void) {
        if let v = self.value { render(v) }
    }
}

public protocol Popup_p: NSView {
    var sizeCallback: ((NSSize) -> Void)? { get set }
    func appear()
    func disappear()
}

open class PopupWrapper: NSStackView, Popup_p {
    public var sizeCallback: ((NSSize) -> Void)? = nil

    public override init(frame: NSRect) {
        super.init(frame: frame)
        self.orientation = .vertical
        self.alignment = .leading
        self.spacing = Constants.Popup.spacing
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open func appear() {}
    open func disappear() {}

    public func apply<T>(_ value: T, to cache: PopupCache<T>, render: @escaping (T) -> Void) {
        DispatchQueue.main.async {
            cache.apply(value, visible: self.window?.isVisible ?? false, render: render)
        }
    }

    public func replay<T>(_ cache: PopupCache<T>, render: (T) -> Void) {
        cache.replay(render: render)
    }
}

public class PopupWindow: NSWindow, NSWindowDelegate {
    private let viewController: PopupViewController
    internal var locked: Bool = false

    public init(view: Popup_p?, visibilityCallback: @escaping (_ state: Bool) -> Void) {
        self.viewController = PopupViewController()
        self.viewController.setup(view: view)

        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: self.viewController.view.frame.width,
                height: self.viewController.view.frame.height
            ),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        self.viewController.visibilityCallback = { [weak self] state in
            self?.locked = false
            visibilityCallback(state)
        }

        self.titleVisibility = .hidden
        self.contentViewController = self.viewController
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .default
        self.collectionBehavior = .moveToActiveSpace
        self.backgroundColor = .clear
        self.hasShadow = true
        self.setIsVisible(false)
        self.delegate = self
    }

    public func windowWillMove(_ notification: Notification) {
        // 拖动后钉住：失焦不自动关闭
        self.locked = true
    }

    public func windowDidResignKey(_ notification: Notification) {
        if self.locked {
            return
        }
        self.setIsVisible(false)
    }
}

internal class PopupViewController: NSViewController {
    fileprivate var visibilityCallback: (_ state: Bool) -> Void = {_ in }
    private var popup: PopupView

    public init() {
        self.popup = PopupView(frame: NSRect(
            x: 0,
            y: 0,
            width: Constants.Popup.width + (Constants.Popup.margins * 2),
            height: Constants.Popup.height
        ))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = self.popup
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        self.popup.appear()
        self.visibilityCallback(true)
        NotificationCenter.default.post(name: .popupVisibilityChanged, object: nil, userInfo: ["state": true])
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        self.popup.disappear()
        self.visibilityCallback(false)
        NotificationCenter.default.post(name: .popupVisibilityChanged, object: nil, userInfo: ["state": false])
    }

    fileprivate func setup(view: Popup_p?) {
        self.popup.setView(view)
    }
}

internal class PopupView: NSView {
    private var view: Popup_p? = nil

    private var foreground: NSVisualEffectView
    private var background: NSView
    private let body: NSScrollView

    override var intrinsicContentSize: CGSize {
        return CGSize(width: self.frame.width, height: self.frame.height)
    }

    override init(frame: NSRect) {
        self.body = NSScrollView(frame: NSRect(
            x: Constants.Popup.margins,
            y: Constants.Popup.margins,
            width: frame.width - Constants.Popup.margins*2,
            height: frame.height - Constants.Popup.margins*2
        ))

        self.foreground = NSVisualEffectView(frame: frame)
        self.foreground.material = .titlebar
        self.foreground.blendingMode = .behindWindow
        self.foreground.state = .active
        self.foreground.wantsLayer = true
        self.foreground.layer?.cornerRadius = 6

        self.background = NSView(frame: frame)
        self.background.wantsLayer = true
        self.foreground.addSubview(self.background)

        super.init(frame: frame)

        self.body.drawsBackground = false
        self.body.translatesAutoresizingMaskIntoConstraints = true
        self.body.borderType = .noBorder
        self.body.hasVerticalScroller = true
        self.body.hasHorizontalScroller = false
        self.body.autohidesScrollers = true
        self.body.horizontalScrollElasticity = .none

        self.addSubview(self.foreground, positioned: .below, relativeTo: .none)
        self.addSubview(self.body)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        self.background.layer?.backgroundColor = isDarkMode ? .clear : NSColor.white.cgColor
    }

    fileprivate func setView(_ view: Popup_p?) {
        self.view = view

        var isScrollVisible: Bool = false
        var size: NSSize = NSSize(
            width: (view?.frame.width ?? Constants.Popup.width) + (Constants.Popup.margins*2),
            height: (view?.frame.height ?? 0) + (Constants.Popup.margins*2)
        )

        if let screenHeight = NSScreen.main?.visibleFrame.height, size.height > screenHeight {
            size.height = screenHeight - Constants.Widget.height
            isScrollVisible = true
        }
        if let screenWidth = NSScreen.main?.visibleFrame.width, size.width > screenWidth {
            size.width = screenWidth
        }

        self.setFrameSize(size)
        self.foreground.setFrameSize(size)
        self.background.setFrameSize(size)
        self.resizeBody(size, scrollVisible: isScrollVisible)

        if let view = view {
            self.body.documentView = view
            view.sizeCallback = { [weak self] size in
                self?.recalculateHeight(size)
            }
        }
    }

    internal func appear() {
        self.view?.appear()
        self.display()
        self.body.subviews.first?.display()
        if let documentView = self.body.documentView {
            documentView.scroll(NSPoint(x: 0, y: documentView.bounds.size.height))
        }
    }

    internal func disappear() {
        self.view?.disappear()
    }

    private func recalculateHeight(_ size: NSSize) {
        var isScrollVisible: Bool = false
        var windowSize: NSSize = NSSize(
            width: size.width + (Constants.Popup.margins*2),
            height: size.height + (Constants.Popup.margins*2)
        )

        if let screenHeight = NSScreen.main?.visibleFrame.height, windowSize.height > screenHeight {
            windowSize.height = screenHeight - Constants.Widget.height
            isScrollVisible = true
        }
        if let screenWidth = NSScreen.main?.visibleFrame.width, windowSize.width > screenWidth {
            windowSize.width = screenWidth
        }

        self.window?.setContentSize(windowSize)
        self.foreground.setFrameSize(windowSize)
        self.background.setFrameSize(windowSize)
        self.resizeBody(windowSize, scrollVisible: isScrollVisible)
    }

    private func resizeBody(_ windowSize: NSSize, scrollVisible: Bool) {
        let offset: CGFloat = scrollVisible ? 20 : 0
        self.body.frame = NSRect(
            x: Constants.Popup.margins,
            y: Constants.Popup.margins,
            width: windowSize.width - (Constants.Popup.margins*2) + offset,
            height: windowSize.height - (Constants.Popup.margins*2)
        )
    }
}

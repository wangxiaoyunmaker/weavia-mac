import AppKit

final class MaterialImageView: NSImageView {
    var onActivate: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onActivate?() }
    override func resetCursorRects() { if onActivate != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func accessibilityPerformPress() -> Bool { guard let onActivate else { return false }; onActivate(); return true }
}

final class MaterialTitleField: NSTextField {
    var onActivate: (() -> Void)? { didSet { window?.invalidateCursorRects(for: self) } }
    init(_ title: String) {
        super.init(frame: .zero)
        stringValue = title
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        font = .systemFont(ofSize: 14, weight: .semibold)
        textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        setAccessibilityRole(.link)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with event: NSEvent) { onActivate?() }
    override func resetCursorRects() { if onActivate != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func accessibilityPerformPress() -> Bool { guard let onActivate else { return false }; onActivate(); return true }
}

enum MaterialNavigation {
    @discardableResult static func open(_ value: String?, browserBundleID: String? = nil) -> Bool {
        guard let value, let url = URL(string: value), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return false }
        if !url.isFileURL, let browserBundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return true
        }
        return NSWorkspace.shared.open(url)
    }
}

final class MaterialPreviewController: NSWindowController {
    private static var retained: [MaterialPreviewController] = []
    private let scroll = NSScrollView()
    private var sourceURL: String?
    private var originalURL: String?
    private var browserBundleID: String?

    static func dismissVisible() { retained.forEach { $0.window?.orderOut(nil) } }
    static func restoreNormalLevels() { retained.forEach { $0.window?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4) } }

    static func show(title: String, text: String?, image: NSImage?, sourceURL: String?, originalURL: String?, rendered: Bool, browserBundleID: String? = nil, level: NSWindow.Level? = nil) {
        let controller = MaterialPreviewController(title: title, text: text, image: image, sourceURL: sourceURL, originalURL: originalURL, rendered: rendered, browserBundleID: browserBundleID)
        retained.removeAll { $0.window?.isVisible != true }
        retained.append(controller)
        if let level { controller.window?.level = level }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(title: String, text: String?, image: NSImage?, sourceURL: String?, originalURL: String?, rendered: Bool, browserBundleID: String?) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        self.sourceURL = sourceURL
        self.originalURL = originalURL
        self.browserBundleID = browserBundleID
        window.title = title
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 360)
        window.center()
        let root = NSView()
        window.contentView = root
        let caption = NSTextField(labelWithString: image == nil ? "文字全文" : rendered ? "浏览器可见区域截图 · 可缩放查看；高清原图请在浏览器打开" : "图片预览 · 支持缩放")
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor
        let minus = NSButton(title: "−", target: self, action: #selector(zoomOut))
        let plus = NSButton(title: "+", target: self, action: #selector(zoomIn))
        let actual = NSButton(title: "100%", target: self, action: #selector(actualSize))
        let fit = NSButton(title: "适合窗口", target: self, action: #selector(fitImage))
        let source = NSButton(title: "返回来源网页", target: self, action: #selector(openSource))
        let original = NSButton(title: "浏览器打开原图", target: self, action: #selector(openOriginal))
        source.isEnabled = sourceURL != nil
        original.isEnabled = originalURL != nil
        original.isHidden = image == nil
        [minus, plus, actual, fit].forEach { $0.isHidden = image == nil }
        let toolbar = NSStackView(views: [minus, plus, actual, fit, source, original])
        toolbar.spacing = 8
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        if let image {
            let scale = max(1, window.backingScaleFactor)
            let size = image.representations.first.map { NSSize(width: CGFloat(max(1, $0.pixelsWide)) / scale, height: CGFloat(max(1, $0.pixelsHigh)) / scale) } ?? image.size
            let view = NSImageView(frame: NSRect(origin: .zero, size: size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            scroll.documentView = view
            scroll.allowsMagnification = true
            scroll.minMagnification = 0.05
            scroll.maxMagnification = 8
        } else {
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 750, height: 540))
            view.string = text ?? title
            view.font = .systemFont(ofSize: 14)
            view.isEditable = false
            view.isSelectable = true
            view.textContainerInset = NSSize(width: 20, height: 20)
            view.isVerticallyResizable = true
            view.autoresizingMask = [.width]
            view.textContainer?.widthTracksTextView = true
            scroll.documentView = view
        }
        [caption, toolbar, scroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), caption.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            toolbar.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 8), toolbar.leadingAnchor.constraint(equalTo: caption.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        window.contentView?.layoutSubtreeIfNeeded()
        if image != nil { fitImage() }
    }

    required init?(coder: NSCoder) { nil }
    @objc private func zoomIn() { scroll.magnification = min(8, scroll.magnification * 1.25) }
    @objc private func zoomOut() { scroll.magnification = max(0.05, scroll.magnification / 1.25) }
    @objc private func actualSize() { scroll.magnification = 1 }
    @objc private func fitImage() {
        guard let view = scroll.documentView else { return }
        scroll.magnification = max(0.05, min(1, min(scroll.contentSize.width / max(1, view.frame.width), scroll.contentSize.height / max(1, view.frame.height))))
    }
    @objc private func openSource() { if MaterialNavigation.open(sourceURL, browserBundleID: browserBundleID) { window?.orderOut(nil) } }
    @objc private func openOriginal() { if MaterialNavigation.open(originalURL, browserBundleID: browserBundleID) { window?.orderOut(nil) } }
}

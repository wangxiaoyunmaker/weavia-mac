import AppKit
import ApplicationServices
import ScreenCaptureKit

struct ContextSource {
    let name: String
    let bundleID: String?
    let pid: pid_t
    static func current() -> ContextSource {
        let app = NSWorkspace.shared.frontmostApplication
        return ContextSource(name: app?.localizedName ?? "当前应用", bundleID: app?.bundleIdentifier, pid: app?.processIdentifier ?? 0)
    }
}

enum SelectedContextReader {
    static func read(_ source: ContextSource, completion: @escaping (String, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var text = "", url: String?
            if let bundle = source.bundleID, BrowserCaptureRequest.supportedBrowsers.contains(bundle) {
                let safari = bundle == "com.apple.Safari"
                let js = "JSON.stringify({text:(getSelection()?.toString()||'').slice(0,16000),url:location.href})"
                let command = safari ? "do JavaScript \(BrowserCaptureRequest.quoted(js)) in current tab of front window" : "execute active tab of front window javascript \(BrowserCaptureRequest.quoted(js))"
                let script = "with timeout of 5 seconds\n tell application id \(BrowserCaptureRequest.quoted(bundle))\nreturn \(command)\nend tell\nend timeout"
                var error: NSDictionary?
                if let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
                   let data = result.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], error == nil {
                    text = value["text"] as? String ?? ""; url = value["url"] as? String
                }
            }
            if text.isEmpty, source.pid != 0, AXIsProcessTrusted() {
                let app = AXUIElementCreateApplication(source.pid)
                var focused: CFTypeRef?
                if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused,
                   CFGetTypeID(focused) == AXUIElementGetTypeID() {
                    var value: CFTypeRef?
                    AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value)
                    text = value as? String ?? ""
                }
            }
            let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16000))
            DispatchQueue.main.async { completion(clean, url) }
        }
    }
}

struct ContextStroke {
    var id = UUID()
    enum Tool: Int { case rectangle, lasso, pen }
    let tool: Tool
    var points: [NSPoint]
    var bounds: NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    func path(offset: NSPoint = .zero) -> NSBezierPath {
        let path = NSBezierPath(); path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round
        guard let first = points.first else { return path }
        if tool == .rectangle { path.appendRect(bounds.offsetBy(dx: -offset.x, dy: -offset.y)) }
        else {
            path.move(to: NSPoint(x: first.x - offset.x, y: first.y - offset.y))
            points.dropFirst().forEach { path.line(to: NSPoint(x: $0.x - offset.x, y: $0.y - offset.y)) }
            if tool == .lasso { path.close() }
        }
        return path
    }
}

/// One open annotation session can confirm multiple messages without closing its surface.
final class ContextCaptureBatch {
    private let context: CompanionContext
    private let project: String
    private let source: ContextSource
    let sessionID: UUID
    private(set) var strokeAssets: [UUID: UUID] = [:]
    private(set) var selectionAssets: [String: UUID] = [:]
    init(context: CompanionContext, source: ContextSource) {
        self.context = context; self.project = context.project; self.source = source
        sessionID = context.beginCaptureSession()
    }
    var referenceIDs: [UUID] { context.currentAssets.map(\.id) }
    func finish() { context.endCaptureSession(sessionID) }
    var confirmedStrokeIDs: Set<UUID> {
        let ids = Set(context.currentAssets.map(\.id))
        return Set(strokeAssets.filter { ids.contains($0.value) }.map(\.key))
    }
    func selectionIsConfirmed(_ text: String) -> Bool {
        guard let id = selectionAssets[text] else { return false }
        return context.currentAssets.contains { $0.id == id }
    }
    func reconcileUndo(strokes: [ContextStroke]) {
        let live = Set(strokes.map(\.id))
        for (stroke, asset) in Array(strokeAssets) where !live.contains(stroke) {
            strokeAssets.removeValue(forKey: stroke); context.remove(asset)
        }
    }
    func removedReferences() -> (strokes: Set<UUID>, selections: Set<String>) {
        let live = Set(context.currentAssets.map(\.id))
        let removedStrokes = strokeAssets.filter { !live.contains($0.value) }
        let removedSelections = selectionAssets.filter { !live.contains($0.value) }
        for key in removedStrokes.keys { strokeAssets.removeValue(forKey: key) }
        for key in removedSelections.keys { selectionAssets.removeValue(forKey: key) }
        return (Set(removedStrokes.keys), Set(removedSelections.keys))
    }
    @discardableResult func confirm(strokes: [ContextStroke], image: NSImage?, text: String, includeText: Bool, sourceURL: String?) throws -> Int {
        guard context.project == project, context.activeCaptureSessionID == sessionID else { throw issue("已不是当前灵感会话，请在当前界面重新圈画。") }
        let pending = strokes.enumerated().filter { strokeAssets[$0.element.id] == nil }
        let existingText = context.currentAssets.first { $0.image == nil && $0.text == text && $0.sourceApp == source.name }
        let addText = includeText && !text.isEmpty && !selectionIsConfirmed(text) && existingText == nil
        guard context.currentAssets.count + pending.count + (addText ? 1 : 0) <= 8 else { throw issue("上下文最多 8 份。请撤销多余圈画，或在「上下文」移除旧内容后发送。") }
        var crops: [(ContextStroke, Int, NSImage, NSImage)] = []
        for (index, stroke) in pending {
            guard let image, let crop = ContextCrop.crop(image, stroke: stroke) else { throw issue("有一处选区无法截取，请撤销后重新圈画。") }
            crops.append((stroke, index + 1, crop.raw, crop.annotated))
        }
        var added = 0
        if addText {
            let asset = CompanionContextAsset(title: "选中文字", text: text, image: nil, sourceApp: source.name, sourceURL: sourceURL, kind: "selected_text", sourceBrowserBundleID: source.bundleID)
            context.add(asset); selectionAssets[text] = asset.id; added += 1
        } else if includeText, !text.isEmpty, let existingText { selectionAssets[text] = existingText.id }
        for (stroke, index, raw, annotated) in crops {
            let asset = CompanionContextAsset(title: "圈画 \(index)", text: "", image: annotated, sourceApp: source.name, sourceURL: sourceURL, kind: stroke.tool == .pen ? "pen_annotation" : "selected_region", preparing: true, sourceBrowserBundleID: source.bundleID)
            context.add(asset); strokeAssets[stroke.id] = asset.id; added += 1
            DesignOCR.read(raw) { [weak context] in context?.completeOCR(asset.id, text: $0) }
        }
        return added
    }
    private func issue(_ text: String) -> Error { NSError(domain: "ContextCapture", code: 409, userInfo: [NSLocalizedDescriptionKey: text]) }
}

enum ContextCrop {
    static func rect(for stroke: ContextStroke, in size: NSSize) -> NSRect {
        stroke.bounds.insetBy(dx: -12, dy: -12).intersection(NSRect(origin: .zero, size: size)).integral
    }
    static func crop(_ image: NSImage, stroke: ContextStroke) -> (raw: NSImage, annotated: NSImage)? {
        let rect = rect(for: stroke, in: image.size)
        guard rect.width > 5, rect.height > 5,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sx = CGFloat(cg.width) / image.size.width, sy = CGFloat(cg.height) / image.size.height
        let pixels = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
        guard let clipped = cg.cropping(to: pixels) else { return nil }
        let raw = NSImage(cgImage: clipped, size: rect.size)
        let annotated = NSImage(size: rect.size, flipped: true) { _ in
            raw.draw(in: NSRect(origin: .zero, size: rect.size), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.97, alpha: 1).setStroke()
            stroke.path(offset: rect.origin).stroke()
            return true
        }
        return (raw, annotated)
    }
}

private final class ContextCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class ContextDrawingView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var snapshot: NSImage?
    var strokes: [ContextStroke] = []
    var tool = ContextStroke.Tool.rectangle
    var confirmedIDs = Set<UUID>()
    var onChange: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onFocusPrompt: (() -> Void)?
    private var drawing = false
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        snapshot?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.12).setFill(); bounds.fill()
        for (index, stroke) in strokes.enumerated() {
            if let snapshot {
                let clip = NSGraphicsContext.current
                clip?.saveGraphicsState()
                let path = stroke.path()
                if stroke.tool != .pen { path.addClip() }
                else { NSBezierPath(rect: ContextCrop.rect(for: stroke, in: bounds.size)).addClip() }
                snapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
                clip?.restoreGraphicsState()
            }
            (confirmedIDs.contains(stroke.id) ? NSColor.systemBlue : NSColor.systemPurple).setStroke(); stroke.path().stroke()
            let p = stroke.bounds.origin
            let label = (confirmedIDs.contains(stroke.id) ? " ✓ \(index + 1) " : " \(index + 1) ") as NSString
            label.draw(at: NSPoint(x: p.x, y: max(0, p.y - 21)), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white, .backgroundColor: NSColor.systemPurple])
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard snapshot != nil, strokes.count < 8 else { NSSound.beep(); return }
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        strokes.append(ContextStroke(tool: tool, points: [p])); drawing = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard drawing, !strokes.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)
        if tool == .rectangle { strokes[strokes.count - 1].points = [strokes.last!.points[0], p] }
        else { strokes[strokes.count - 1].points.append(p) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard drawing else { return }; drawing = false
        if let last = strokes.last, last.bounds.width + last.bounds.height < 8 { strokes.removeLast() }
        needsDisplay = true; onChange?(); onFocusPrompt?()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else if event.keyCode == 36 { onCommit?() }
        else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" { undoStroke() }
        else if event.charactersIgnoringModifiers == "/" { onFocusPrompt?() }
        else { super.keyDown(with: event) }
    }
    func undoStroke() { if !strokes.isEmpty { strokes.removeLast(); needsDisplay = true; onChange?() } }
}

private final class CaptureIconButton: NSButton {
    private let handler: () -> Void
    private let glyph = NSImageView()
    private let countText = NSTextField(labelWithString: "")
    private var countSize = NSSize.zero
    private var widthConstraint: NSLayoutConstraint!
    private var hovering = false
    private var pressing = false
    var isSelected = false { didSet { setAccessibilitySelected(isSelected); refresh() } }
    override var isEnabled: Bool { didSet { refresh() } }

    init(_ symbol: String, label: String, id: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        title = ""; isBordered = false; wantsLayer = true; layer?.cornerRadius = 6
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        glyph.imageScaling = .scaleProportionallyDown
        countText.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countText.usesSingleLineMode = true
        countText.isHidden = true
        [glyph, countText].forEach { $0.setAccessibilityElement(false); addSubview($0) }
        setAccessibilityLabel(label); setAccessibilityIdentifier(id); toolTip = label
        target = self; self.action = #selector(invoke)
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([widthConstraint, heightAnchor.constraint(equalToConstant: 32)])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    override func accessibilityFrame() -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }
    // All visual states are drawn by the same layer and content views. Do not let
    // NSButtonCell add a second, system-dependent highlight on top of them.
    override func draw(_ dirtyRect: NSRect) {}
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressing = true; refresh()
        defer { pressing = false; refresh() }
        super.mouseDown(with: event)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func layout() {
        super.layout()
        if countText.isHidden { glyph.frame = NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16) }
        else {
            glyph.frame = NSRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
            countText.frame = NSRect(x: 30, y: floor((bounds.height - countSize.height) / 2), width: countSize.width, height: countSize.height)
        }
    }
    func setCount(_ count: Int) {
        countText.stringValue = String(count); countText.isHidden = false
        // NSTextField needs its cell insets and full line height in addition to
        // the glyph width; measuring only the glyph clips digits such as “2”.
        let fitting = countText.fittingSize
        countSize = NSSize(width: ceil(fitting.width) + 2, height: ceil(fitting.height))
        widthConstraint.constant = max(48, 38 + countSize.width)
        setAccessibilityValue(String(count)); needsLayout = true
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovering = false; refresh() }
    private func refresh() {
        func rgb(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        let pressed = pressing && hovering
        let tint: NSColor
        let fill: NSColor
        if !isEnabled { tint = rgb(0xBFBFBF); fill = isSelected ? rgb(0xF5F5F5) : .clear }
        else if isSelected {
            tint = rgb(pressed ? 0x0958D9 : 0x1677FF)
            fill = rgb(pressed ? 0x91CAFF : hovering ? 0xBAE0FF : 0xE6F4FF)
        } else {
            tint = rgb(0x262626)
            fill = pressed ? rgb(0xE8E8E8) : hovering ? rgb(0xF5F5F5) : .clear
        }
        glyph.contentTintColor = tint; countText.textColor = tint
        layer?.backgroundColor = fill.cgColor
    }
    @objc private func invoke() { handler() }
}

final class ContextCaptureController: NSObject {
    private let context: CompanionContext
    private var panel: ContextCapturePanel?
    private var view: ContextDrawingView?
    private var source = ContextSource(name: "当前应用", bundleID: nil, pid: 0)
    private var selectedText = ""
    private var selectionReady = false
    private var sourceURL: String?
    private var selectionToggle: CaptureIconButton?
    private var status: NSTextField?
    private var generation = UUID()
    private var batch: ContextCaptureBatch?
    private var observation: UUID?
    private var contextButton: CaptureIconButton?
    private var toolButtons: [CaptureIconButton] = []
    private var validationError: String?
    private(set) var isActive = false
    var displayFrame: NSRect? { panel?.frame }
    var onFinish: ((Bool) -> Void)?
    var onReady: (() -> Void)?
    var onFocusPrompt: (() -> Void)?
    var onReviewContext: (() -> Void)?
    var onContextConfirmed: (() -> Void)?
    var onCollectToTray: (([String]) -> Void)?

    init(context: CompanionContext) { self.context = context }
    func begin(source: ContextSource) {
        guard !isActive else { return }
        isActive = true; self.source = source; selectedText = ""; sourceURL = nil; selectionReady = false
        validationError = nil
        batch = ContextCaptureBatch(context: context, source: source)
        observation = context.observe { [weak self] in self?.contextChanged() }
        let token = UUID(); generation = token
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main else { cancel(); return }
        SelectedContextReader.read(source) { [weak self] text, url in
            guard let self, self.generation == token, self.isActive, !self.selectionReady else { return }
            self.selectedText = text; self.sourceURL = url; self.selectionReady = true; self.updateSelection()
        }
        Task { @MainActor [weak self] in
            let image = await Self.snapshot(screen)
            guard let self, self.isActive, self.generation == token else { return }
            self.present(screen: screen, image: image)
        }
    }
    private static func snapshot(_ screen: NSScreen) async -> NSImage? {
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = content.displays.first(where: { $0.displayID == id.uint32Value }) else { return nil }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration(); config.showsCursor = false
        config.width = Int(screen.frame.width * screen.backingScaleFactor); config.height = Int(screen.frame.height * screen.backingScaleFactor)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return NSImage(cgImage: image, size: screen.frame.size)
    }
    private func present(screen: NSScreen, image: NSImage?) {
        let panel = ContextCapturePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
        panel.title = "圈画上下文"
        let view = ContextDrawingView(frame: NSRect(origin: .zero, size: screen.frame.size)); view.snapshot = image
        view.onCommit = { [weak self] in self?.onFocusPrompt?() }; view.onCancel = { [weak self] in self?.cancel() }
        view.onFocusPrompt = { [weak self] in self?.onFocusPrompt?() }
        view.onChange = { [weak self] in
            guard let self else { return }; self.validationError = nil; self.batch?.reconcileUndo(strokes: self.view?.strokes ?? []); self.updateSelection()
        }
        toolButtons = zip(["rectangle.dashed", "lasso", "pencil.tip"], ["框选", "套索", "画笔"]).enumerated().map { index, item in
            CaptureIconButton(item.0, label: item.1, id: "capture-tool-\(index)") { [weak self] in self?.selectTool(index) }
        }
        toolButtons[0].isSelected = true
        let tools = NSStackView(views: toolButtons); tools.spacing = 2
        let selection = CaptureIconButton("text.quote", label: "携带选中文字", id: "capture-selection") { [weak self] in
            guard let self, let toggle = self.selectionToggle else { return }
            toggle.isSelected.toggle(); self.selectionToggled()
        }
        selection.isSelected = true
        let undo = CaptureIconButton("arrow.uturn.backward", label: "撤销圈画", id: "capture-undo") { [weak self, weak view] in view?.undoStroke(); self?.onFocusPrompt?() }
        undo.toolTip = "撤销圈画；之前的回答仍会保留"
        let cancel = CaptureIconButton("xmark", label: "结束圈画", id: "capture-close") { [weak self] in self?.cancel() }
        cancel.toolTip = "结束圈画（Esc）"
        let commit = CaptureIconButton("checkmark.square", label: "保存选区", id: "capture-save") { [weak self] in if self?.commit() == true { self?.onFocusPrompt?() } }
        commit.toolTip = "保存选区到本轮上下文；也可直接输入问题并按 Enter 一起发送"
        let collect = CaptureIconButton("tray.and.arrow.down", label: "放入托盘", id: "capture-collect") { [weak self] in self?.collectToTray() }
        collect.toolTip = "将本轮选区放入灵感托盘"
        let context = CaptureIconButton("square.stack", label: "本轮选区", id: "capture-context") { [weak self] in self?.onReviewContext?() }
        self.contextButton = context
        context.setCount(0)
        func divider() -> NSView {
            let line = NSBox(); line.boxType = .separator
            line.widthAnchor.constraint(equalToConstant: 1).isActive = true; line.heightAnchor.constraint(equalToConstant: 18).isActive = true
            return line
        }
        let buttons = NSStackView(views: [tools, undo, divider(), selection, commit, collect, context, divider(), cancel]); buttons.spacing = 4
        let status = NSTextField(wrappingLabelWithString: "")
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.isHidden = true
        status.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
        let bar = NSStackView(views: [buttons, status]); bar.orientation = .vertical; bar.alignment = .leading; bar.spacing = 6; bar.detachesHiddenViews = true
        bar.setAccessibilityIdentifier("capture-toolbar"); bar.setAccessibilityElement(true); bar.setAccessibilityRole(.toolbar); bar.setAccessibilityLabel("圈画工具栏")
        bar.wantsLayer = true; bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; bar.layer?.cornerRadius = 10
        bar.layer?.borderWidth = 1; bar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        bar.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(bar)
        NSLayoutConstraint.activate([bar.centerXAnchor.constraint(equalTo: view.centerXAnchor), bar.topAnchor.constraint(equalTo: view.topAnchor, constant: screen.frame.maxY - screen.visibleFrame.maxY + 12)])
        panel.contentView = view; self.panel = panel; self.view = view; selectionToggle = selection; self.status = status
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); panel.makeFirstResponder(view)
        updateSelection()
        onReady?()
    }
    private func contextChanged() {
        if let removed = batch?.removedReferences() {
            view?.strokes.removeAll { removed.strokes.contains($0.id) }
            if removed.selections.contains(selectedText) { selectionToggle?.isSelected = false }
        }
        updateSelection()
    }
    private func updateSelection() {
        let textConfirmed = batch?.selectionIsConfirmed(selectedText) == true
        selectionToggle?.isHidden = selectedText.isEmpty
        selectionToggle?.toolTip = "\(textConfirmed ? "已保存" : "携带")选中文字（\(selectedText.count) 字）：\(selectedText.prefix(120))"
        if textConfirmed { selectionToggle?.isSelected = true }
        selectionToggle?.isEnabled = !selectedText.isEmpty && !textConfirmed
        contextButton?.toolTip = "查看本轮上下文（\(context.count) 份）；历史圈选不会作为本轮附件发送"
        contextButton?.setCount(context.count)
        view?.confirmedIDs = batch?.confirmedStrokeIDs ?? []; view?.needsDisplay = true
        let message = validationError ?? (view?.snapshot == nil ? unavailableSnapshotMessage : nil)
        status?.stringValue = message ?? ""; status?.isHidden = message == nil
    }
    private var unavailableSnapshotMessage: String {
        guard #available(macOS 14.0, *) else { return "圈画截图需要 macOS 14 或更新版本。" }
        guard CGPreflightScreenCaptureAccess() else {
            return "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 WEAVIA，再退出重开；菜单栏 ↖ 有权限帮助。"
        }
        return "已允许屏幕录制，但系统暂未返回截图。请结束圈画后重试；仍失败时退出重开 WEAVIA。"
    }
    private func selectTool(_ index: Int) {
        view?.tool = ContextStroke.Tool(rawValue: index) ?? .rectangle
        for (i, button) in toolButtons.enumerated() { button.isSelected = i == index }
        panel?.makeFirstResponder(view)
    }
    @objc private func selectionToggled() { validationError = nil; updateSelection(); onFocusPrompt?() }
    func pasteText() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        selectedText = String(text.prefix(16000)); sourceURL = nil; selectionReady = true; validationError = nil; selectionToggle?.isSelected = true; updateSelection()
        onFocusPrompt?()
    }
    @discardableResult func commit() -> Bool {
        guard isActive, let view, let batch else { return false }
        guard selectionReady else { validationError = "正在读取来源选区，请稍等片刻再发送；输入的问题会保留。"; updateSelection(); return false }
        do {
            let count = try batch.confirm(strokes: view.strokes, image: view.snapshot, text: selectedText, includeText: selectionToggle?.isSelected == true, sourceURL: sourceURL)
            validationError = nil; updateSelection(); if count > 0 { onContextConfirmed?() }; return true
        } catch { validationError = error.localizedDescription; updateSelection(); NSSound.beep(); return false }
    }
    private func collectToTray() {
        guard commit(), let batch else { return }
        let materials = context.collectCurrentReferences(batch.referenceIDs)
        guard !materials.isEmpty else { validationError = "请先框选、圈画或选择文字，再放入托盘。"; updateSelection(); return }
        validationError = "本次 \(materials.count) 份选区已放入托盘；可逐张备注和选择项目。"
        updateSelection(); onCollectToTray?(materials.map(\.id))
    }
    func cancel() { guard isActive else { return }; close(); onFinish?(false) }
    private func close() {
        if let observation { context.unobserve(observation) }; observation = nil; batch?.finish(); batch = nil; contextButton = nil; toolButtons = []
        generation = UUID(); isActive = false; panel?.orderOut(nil); panel = nil; view = nil; selectionToggle = nil; status = nil; selectedText = ""; sourceURL = nil
    }
}

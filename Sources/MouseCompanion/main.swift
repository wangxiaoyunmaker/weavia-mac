import AppKit
import Carbon
import QuartzCore
import Security

private extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private enum Palette {
    // Ant Design v5 global and alias tokens.
    static let ink = NSColor(hex: 0x1F1F1F)
    static let secondary = NSColor(hex: 0x595959)
    static let tertiary = NSColor(hex: 0x8C8C8C)
    static let quaternary = NSColor(hex: 0xBFBFBF)
    static let panel = NSColor(hex: 0xFFFFFF)
    static let canvas = NSColor(hex: 0xF5F5F5)
    static let soft = NSColor(hex: 0xFAFAFA)
    static let border = NSColor(hex: 0xD9D9D9)
    static let borderSecondary = NSColor(hex: 0xF0F0F0)
    static let accent = NSColor(hex: 0x1677FF)
    static let accentHover = NSColor(hex: 0x4096FF)
    static let accentActive = NSColor(hex: 0x0958D9)
    static let accentSoft = NSColor(hex: 0xE6F4FF)
    static let accentBorder = NSColor(hex: 0x91CAFF)
    static let green = NSColor(hex: 0x52C41A)
    static let greenSoft = NSColor(hex: 0xF6FFED)
    static let amber = NSColor(hex: 0xFA8C16)
    static let amberSoft = NSColor(hex: 0xFFF7E6)
    static let red = NSColor(hex: 0xFF4D4F)
}

private enum AntMetrics {
    static let radiusXS: CGFloat = 2
    static let radiusSM: CGFloat = 4
    static let radius: CGFloat = 6
    static let radiusLG: CGFloat = 8
    static let radiusXL: CGFloat = 12
    static let spaceXXS: CGFloat = 4
    static let spaceXS: CGFloat = 8
    static let spaceSM: CGFloat = 12
    static let space: CGFloat = 16
    static let spaceLG: CGFloat = 24
    static let control: CGFloat = 32
    static let controlLG: CGFloat = 40
}

private enum AntType {
    static let caption: CGFloat = 12
    static let body: CGFloat = 14
    static let heading: CGFloat = 16
    static let pageTitle: CGFloat = 24
    static func font(_ size: CGFloat = body, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
}

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class TrayHeaderDragView: FlippedView {
    var onDragging: ((Bool) -> Void)?
    var onMoved: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var moved = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }
    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        moved = false
        onDragging?(true)
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x, dy = current.y - startMouse.y
        guard moved || abs(dx) + abs(dy) > 4 else { return }
        moved = true
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        onDragging?(false)
        if moved { onMoved?() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

private final class CompanionDragView: FlippedView {
    var onClick: (() -> Void)?
    var onMoved: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    private var mouseDownLocation = NSPoint.zero
    private var windowOrigin = NSPoint.zero
    private var didDrag = false

    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin ?? .zero
        didDrag = false
        onDragStateChanged?(true)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownLocation.x
        let dy = current.y - mouseDownLocation.y
        if abs(dx) + abs(dy) > 3 { didDrag = true }
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy))
        onMoved?()
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        onDragStateChanged?(false)
        if !didDrag { onClick?() }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

private final class AgentCursorView: NSView {
    private let glowLayer = CAShapeLayer()
    private let auraContainer = CALayer()
    private let auraLayer = CAGradientLayer()
    private let auraMask = CAShapeLayer()
    private let cursorLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        glowLayer.fillColor = NSColor.clear.cgColor
        glowLayer.strokeColor = NSColor(hex: 0x8055FF, alpha: 0.75).cgColor
        glowLayer.lineWidth = 2.8
        glowLayer.lineJoin = .round
        glowLayer.shadowColor = NSColor(hex: 0x7965ED).cgColor
        glowLayer.shadowOpacity = 0.78
        glowLayer.shadowRadius = 3.5
        glowLayer.shadowOffset = .zero
        layer?.addSublayer(glowLayer)

        auraLayer.type = .conic
        auraLayer.colors = [
            NSColor(hex: 0x4096FF, alpha: 0.65).cgColor,
            NSColor(hex: 0x722ED1).cgColor,
            NSColor(hex: 0xB7C9FF, alpha: 0.40).cgColor,
            NSColor(hex: 0x1677FF).cgColor,
            NSColor(hex: 0x4096FF, alpha: 0.65).cgColor
        ]
        auraLayer.locations = [0, 0.24, 0.52, 0.78, 1]
        auraLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        auraLayer.endPoint = CGPoint(x: 0.5, y: 0)
        auraMask.fillColor = NSColor.clear.cgColor
        auraMask.strokeColor = NSColor.white.cgColor
        auraMask.lineWidth = 2.8
        auraMask.lineCap = .round
        auraMask.lineJoin = .round
        // Only the color field rotates; the mask stays attached to the cursor contour.
        auraContainer.mask = auraMask
        auraContainer.addSublayer(auraLayer)
        layer?.addSublayer(auraContainer)

        cursorLayer.fillColor = NSColor.white.cgColor
        cursorLayer.strokeColor = NSColor(hex: 0x727FA5, alpha: 0.42).cgColor
        cursorLayer.lineWidth = 0.65
        cursorLayer.lineJoin = .round
        cursorLayer.shadowColor = NSColor(hex: 0x22305A).cgColor
        cursorLayer.shadowOpacity = 0.18
        cursorLayer.shadowRadius = 2
        cursorLayer.shadowOffset = NSSize(width: 0, height: -1)
        layer?.addSublayer(cursorLayer)

        startAnimations()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // AppKit's unflipped view uses a bottom-left origin: the high-y tip points up-left.
        let cursor = CGMutablePath()
        cursor.move(to: CGPoint(x: 10, y: 38))
        cursor.addLine(to: CGPoint(x: 11, y: 10))
        cursor.addLine(to: CGPoint(x: 18, y: 18))
        cursor.addLine(to: CGPoint(x: 24, y: 7))
        cursor.addLine(to: CGPoint(x: 28, y: 9))
        cursor.addLine(to: CGPoint(x: 22, y: 20))
        cursor.addLine(to: CGPoint(x: 33, y: 21))
        cursor.closeSubpath()
        // Scale the 31pt silhouette to 23pt while keeping the surrounding hit area.
        var scale = CGAffineTransform(translationX: 6.3, y: 6.0).scaledBy(x: 0.74, y: 0.74)
        let outline = cursor.copy(using: &scale) ?? cursor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.frame = bounds
        glowLayer.path = outline
        auraContainer.frame = bounds
        auraLayer.frame = bounds
        auraMask.frame = bounds
        auraMask.path = outline
        cursorLayer.frame = bounds
        cursorLayer.path = outline
        CATransaction.commit()
    }

    private func startAnimations() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 3.6
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        auraLayer.add(rotation, forKey: "ai.aura.rotation")

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.65
        pulse.toValue = 1.0
        pulse.duration = 1.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(pulse, forKey: "ai.aura.pulse")
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class AntButton: NSButton {
    enum Kind { case primary, secondary, text }
    private let kind: Kind
    private var tracking: NSTrackingArea?

    init(_ title: String, kind: Kind = .secondary, target: AnyObject? = nil, action: Selector? = nil) {
        self.kind = kind
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        font = AntType.font()
        wantsLayer = true
        layer?.cornerRadius = AntMetrics.radius
        layer?.cornerCurve = .continuous
        apply(hovered: false, active: false)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { apply(hovered: true, active: false) }
    override func mouseExited(with event: NSEvent) { apply(hovered: false, active: false) }
    override func mouseDown(with event: NSEvent) {
        apply(hovered: true, active: true)
        super.mouseDown(with: event)
        apply(hovered: bounds.contains(convert(event.locationInWindow, from: nil)), active: false)
    }

    private func apply(hovered: Bool, active: Bool) {
        switch kind {
        case .primary:
            layer?.backgroundColor = (active ? Palette.accentActive : hovered ? Palette.accentHover : Palette.accent).cgColor
            layer?.borderWidth = 0
            contentTintColor = .white
        case .secondary:
            layer?.backgroundColor = (active ? Palette.accentSoft : Palette.panel).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = (hovered || active ? Palette.accent : Palette.border).cgColor
            contentTintColor = hovered || active ? Palette.accent : Palette.ink
        case .text:
            layer?.backgroundColor = (hovered ? Palette.soft : NSColor.clear).cgColor
            layer?.borderWidth = 0
            contentTintColor = hovered ? Palette.accent : Palette.secondary
        }
    }
}

private final class AntSelect: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = false
        font = AntType.font()
        focusRingType = .none
        menu?.font = AntType.font()
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === self
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: AntMetrics.radius, yRadius: AntMetrics.radius)
        Palette.panel.setFill()
        shape.fill()
        (focused || isHighlighted ? Palette.accent : Palette.border).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: titleOfSelectedItem ?? "", attributes: [
            .font: AntType.font(), .foregroundColor: Palette.ink, .paragraphStyle: paragraph
        ])
        text.draw(in: NSRect(x: 12, y: (bounds.height - 20) / 2, width: bounds.width - 40, height: 20))
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: bounds.width - 21, y: bounds.midY - 2))
        arrow.line(to: NSPoint(x: bounds.width - 17, y: bounds.midY + 2))
        arrow.line(to: NSPoint(x: bounds.width - 13, y: bounds.midY - 2))
        arrow.lineWidth = 1.3
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        Palette.tertiary.setStroke()
        arrow.stroke()
    }
}

private final class AntCheckbox: NSButton {
    init(_ text: String) {
        super.init(frame: .zero)
        title = text
        setButtonType(.switch)
        isBordered = false
        font = AntType.font()
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 1, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let box = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        let checked = state == .on
        (checked ? Palette.accent : Palette.panel).setFill()
        box.fill()
        (checked || isHighlighted || window?.firstResponder === self ? Palette.accent : Palette.border).setStroke()
        box.lineWidth = 1
        box.stroke()
        if checked {
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
            tick.line(to: NSPoint(x: rect.minX + 7, y: rect.maxY - 4))
            tick.line(to: NSPoint(x: rect.maxX - 3, y: rect.minY + 4))
            tick.lineWidth = 1.6
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: title, attributes: [
            .font: AntType.font(), .foregroundColor: Palette.ink, .paragraphStyle: paragraph
        ]).draw(in: NSRect(x: 25, y: (bounds.height - 20) / 2, width: bounds.width - 25, height: 20))
    }
}

private final class AntInputCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let height = (font ?? AntType.font()).boundingRectForFont.height
        return NSRect(x: rect.minX + 12, y: rect.minY + (rect.height - height) / 2, width: max(0, rect.width - 24), height: height)
    }

    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
    }
}

private final class AntInput: NSTextField {
    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        layer?.borderColor = Palette.accent.cgColor
        layer?.shadowColor = Palette.accent.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 2
        layer?.shadowOffset = .zero
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        layer?.borderColor = Palette.border.cgColor
        layer?.shadowOpacity = 0
    }
}

private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Palette.ink) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = AntType.font(size, weight: weight)
    field.textColor = color
    field.maximumNumberOfLines = 0
    return field
}

private func rounded(_ view: NSView, color: NSColor, radius: CGFloat, border: NSColor? = nil) {
    view.wantsLayer = true
    view.layer?.backgroundColor = color.cgColor
    view.layer?.cornerRadius = radius
    view.layer?.cornerCurve = .continuous
    if let border {
        view.layer?.borderColor = border.cgColor
        view.layer?.borderWidth = 1
    }
}

private func elevate(_ view: NSView, level: Int = 2) {
    view.wantsLayer = true
    view.layer?.masksToBounds = false
    view.layer?.shadowColor = NSColor.black.cgColor
    view.layer?.shadowOpacity = level >= 3 ? 0.13 : 0.09
    view.layer?.shadowRadius = level >= 3 ? 18 : 10
    view.layer?.shadowOffset = NSSize(width: 0, height: level >= 3 ? -8 : -4)
}

private func styleInput(_ field: NSTextField) {
    field.font = AntType.font()
    field.isBezeled = false
    field.drawsBackground = true
    field.backgroundColor = Palette.panel
    field.focusRingType = .none
    rounded(field, color: Palette.panel, radius: AntMetrics.radius, border: Palette.border)
}

private func markdownAttributedString(_ markdown: String, baseSize: CGFloat = AntType.body) -> NSAttributedString {
    let output = NSMutableAttributedString()
    let lines = markdown.components(separatedBy: .newlines)
    var inCodeBlock = false

    for (index, originalLine) in lines.enumerated() {
        if originalLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            inCodeBlock.toggle()
            continue
        }

        var line = originalLine
        var size = baseSize
        var weight: NSFont.Weight = .regular
        var color = Palette.ink

        if inCodeBlock {
            let code = NSMutableAttributedString(string: line, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular),
                .foregroundColor: Palette.ink,
                .backgroundColor: Palette.soft
            ])
            output.append(code)
        } else {
            if line.hasPrefix("### ") { line.removeFirst(4); size = AntType.body; weight = .semibold }
            else if line.hasPrefix("## ") { line.removeFirst(3); size = AntType.heading; weight = .semibold }
            else if line.hasPrefix("# ") { line.removeFirst(2); size = AntType.heading; weight = .semibold }
            if line.hasPrefix("> ") { line.removeFirst(2); color = Palette.secondary }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line.replaceSubrange(line.startIndex...line.index(after: line.startIndex), with: "• ") }

            let parsed = (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                .map(NSAttributedString.init) ?? NSAttributedString(string: line)
            let mutable = NSMutableAttributedString(attributedString: parsed)
            let full = NSRange(location: 0, length: mutable.length)
            mutable.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color], range: full)
            let intentKey = NSAttributedString.Key("NSInlinePresentationIntent")
            mutable.enumerateAttribute(intentKey, in: full) { value, range, _ in
                let flags = (value as? NSNumber)?.intValue ?? 0
                if flags & 4 != 0 {
                    mutable.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), .backgroundColor: Palette.soft], range: range)
                } else {
                    var traits: NSFontTraitMask = []
                    if flags & 1 != 0 { traits.insert(.italicFontMask) }
                    if flags & 2 != 0 { traits.insert(.boldFontMask) }
                    if !traits.isEmpty, let font = mutable.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                        mutable.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: range)
                    }
                }
                if flags & 8 != 0 { mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            }
            output.append(mutable)
        }
        if index < lines.count - 1 { output.append(NSAttributedString(string: "\n")) }
    }
    let full = NSRange(location: 0, length: output.length)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3
    paragraph.paragraphSpacing = 5
    output.addAttribute(.paragraphStyle, value: paragraph, range: full)
    return output
}

private struct CaptureItem {
    var id = UUID()
    var title: String
    let source: String
    let kind: String
    var preview: NSImage?
    var sourceURL: String?
    var originalImageURL: String?
    var renderedPreview = false
    var textContent: String?
    var textSource: String?
    var textTruncated = false
    var isLoadingPreview = false
    var previewFailed = false
    var browserContext: BrowserDragContext?
    var browserHint: String?
    var fromBrowserPage = false
    var sourceBrowserBundleID: String?
    var navigationBrowser: String? { browserContext?.bundleID ?? sourceBrowserBundleID }

    init?(material: CompanionMaterial) {
        guard let id = UUID(uuidString: material.id) else { return nil }
        self.id = id; title = material.metadata.rawTitle ?? material.title; source = material.metadata.source; kind = material.metadata.kind
        preview = material.image; sourceURL = material.metadata.sourceURL; originalImageURL = material.metadata.originalImageURL
        renderedPreview = material.metadata.renderedPreview; fromBrowserPage = material.metadata.fromBrowserPage
        sourceBrowserBundleID = material.metadata.browserBundleID
        previewFailed = material.metadata.needsRefresh
        textSource = material.metadata.textSource ?? (material.image == nil ? "captured_text" : "image_ocr")
        textTruncated = material.metadata.textTruncated ?? false
        textContent = textSource == "image_ocr" || material.text.isEmpty ? nil : material.text
    }

    init(title: String, source: String, kind: String, preview: NSImage? = nil, sourceURL: String? = nil, originalImageURL: String? = nil, renderedPreview: Bool = false, textContent: String? = nil, isLoadingPreview: Bool = false, previewFailed: Bool = false, browserContext: BrowserDragContext? = nil, browserHint: String? = nil, fromBrowserPage: Bool = false) {
        self.title = title; self.source = source; self.kind = kind; self.preview = preview; self.sourceURL = sourceURL
        self.originalImageURL = originalImageURL; self.renderedPreview = renderedPreview; self.textContent = textContent
        self.isLoadingPreview = isLoadingPreview; self.previewFailed = previewFailed; self.browserContext = browserContext
        self.browserHint = browserHint; self.fromBrowserPage = fromBrowserPage
    }
    func metadata(preserving old: CompanionMaterial.Metadata = .init()) -> CompanionMaterial.Metadata {
        var result = old
        result.source = source; result.kind = kind; result.sourceURL = sourceURL; result.originalImageURL = originalImageURL
        result.browserBundleID = navigationBrowser; result.renderedPreview = renderedPreview; result.fromBrowserPage = fromBrowserPage
        result.rawTitle = title; result.needsRefresh = isLoadingPreview || previewFailed
        if let textSource { result.textSource = textSource; result.textTruncated = textTruncated }
        return result
    }

    var isPageReference: Bool { kind == "网页卡片" && siteName != nil && !isImageURL }
    var hasNoteBody: Bool { textSource == "browser_note_body" && !(textContent ?? "").isEmpty }
    var evidenceSummary: String {
        if hasNoteBody { return "已读取笔记正文 · \(textContent?.count ?? 0) 字" + (textTruncated ? "（部分）" : "") }
        if isPageReference {
            if !(textContent ?? "").isEmpty { return "仅笔记摘要 / 选段 · 非完整正文" }
            return "未读取笔记正文 · 仅标题、封面 / OCR"
        }
        return textContent == nil ? "图片 / OCR" : "已采集文字 · \(textContent?.count ?? 0) 字"
    }
    var isImageURL: Bool {
        guard let url = sourceURL.flatMap(URL.init(string:)) else { return false }
        return ["png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "tiff", "svg"].contains(url.pathExtension.lowercased())
    }

    var needsWebTitle: Bool {
        guard let url = sourceURL.flatMap(URL.init(string:)), !url.isFileURL else { return false }
        return title.isEmpty || title == url.absoluteString || title == url.host || title == url.lastPathComponent.removingPercentEncoding
            || title.range(of: "^[a-fA-F0-9]{16,}$|^[0-9]{8,}$|^[a-zA-Z0-9_-]{24,}$", options: .regularExpression) != nil
    }

    var siteName: String? {
        guard let url = sourceURL.flatMap(URL.init(string:)), !url.isFileURL, let host = url.host else { return nil }
        if host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") || host == "xhslink.com" { return "小红书" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayTitle: String {
        guard let siteName else { return title }
        if isImageURL, let filename = sourceURL.flatMap(URL.init(string:))?.lastPathComponent.removingPercentEncoding, !filename.isEmpty { return filename }
        if needsWebTitle, isLoadingPreview { return isImageURL ? "正在读取图片…" : "正在读取网页标题…" }
        if needsWebTitle, previewFailed { return isImageURL ? "图片预览暂不可用" : "网页标题暂不可用" }
        return needsWebTitle ? "\(siteName)参考链接" : title
    }

    var sourceSummary: String {
        if let siteName {
            if browserHint != nil { return isPageReference && !hasNoteBody ? "\(siteName) · 正文未读取 · 点重试" : "\(siteName) · 浏览器预览待完成 · 点重试" }
            if isLoadingPreview { return "\(siteName) · 正在加载预览" }
            if previewFailed { return "\(siteName) · 预览读取失败" }
            if fromBrowserPage { return "\(siteName) · 来自当前浏览器页面" }
            return "\(siteName) · 链接已保留"
        }
        return source
    }
}

private struct CanvasCard {
    let item: CaptureItem
    let note: String
    let project: String
    let location: String
    let acceptedSuggestions: [String]
    var suggestionEvidence: [DesignSuggestion] = []
}

private enum PasteboardReader {
    static func read(_ pasteboard: NSPasteboard, sourceApp: String) -> CaptureItem? {
        let image = imageFromPasteboard(pasteboard)

        if let fileString = pasteboard.string(forType: .fileURL), let url = URL(string: fileString) {
            let fileImage = NSImage(contentsOf: url) ?? image
            return CaptureItem(
                title: url.deletingPathExtension().lastPathComponent,
                source: "\(sourceApp) · 本地文件",
                kind: fileImage == nil ? "文件" : "图片",
                preview: fileImage,
                sourceURL: url.absoluteString
            )
        }

        let browserURLs = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")) as? [[String]]
        let plainURL = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = pasteboard.string(forType: .URL) ?? browserURLs?.first?.first
            ?? plainURL.flatMap { value in
                guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !value.contains(where: { $0.isWhitespace }) else { return nil }
                return value
            }
        if let urlString, let url = URL(string: urlString) {
            let fallback = url.lastPathComponent.isEmpty ? (url.host ?? "网页内容") : url.lastPathComponent
            let payload = BrowserDragPayload.read(pasteboard, target: url)
            let suppliedTitle = ["public.url-name", "WebURLNamePboardType"].compactMap {
                pasteboard.string(forType: NSPasteboard.PasteboardType($0))?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.first { !$0.isEmpty && $0 != urlString } ?? browserURLs?.dropFirst().first?.first
            let remoteImage = ["png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "tiff", "svg"].contains(url.pathExtension.lowercased())
            return CaptureItem(
                title: suppliedTitle ?? payload.title ?? fallback.removingPercentEncoding ?? fallback,
                source: "\(sourceApp) · \(url.host ?? "网页")",
                kind: remoteImage ? "图片" : "网页卡片",
                preview: image ?? payload.image,
                sourceURL: url.absoluteString
            )
        }

        if let image {
            return CaptureItem(
                title: "来自 \(sourceApp) 的视觉素材",
                source: "\(sourceApp) · 拖拽图片",
                kind: "图片",
                preview: image,
                sourceURL: nil
            )
        }

        let textTypes: [NSPasteboard.PasteboardType] = [
            .string,
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.utf16-external-plain-text"),
            NSPasteboard.PasteboardType("public.text"),
            NSPasteboard.PasteboardType("public.plain-text"),
            NSPasteboard.PasteboardType("text/plain"),
            NSPasteboard.PasteboardType("com.apple.traditional-mac-plain-text"),
            NSPasteboard.PasteboardType("NSStringPboardType"),
            .html,
            .rtf,
            .rtfd
        ]
        let directText = textTypes.compactMap { pasteboard.string(forType: $0) }.first {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let richTextTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd]
        let attributedText: String? = richTextTypes.compactMap { type in
            guard let data = pasteboard.data(forType: type) else { return nil }
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
                ?? NSAttributedString(rtfd: data, documentAttributes: nil)?.string
        }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let draggedText = directText ?? attributedText
        if let text = draggedText {
            let clean = text.replacingOccurrences(of: "\n", with: " ")
            let title = clean.count > 42 ? String(clean.prefix(42)) + "…" : clean
            return CaptureItem(
                title: title,
                source: "\(sourceApp) · 文本选段",
                kind: "文字卡片",
                preview: nil,
                sourceURL: nil,
                textContent: text
            )
        }
        return nil
    }

    private static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) { return image }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) { return image }
        return NSImage(pasteboard: pasteboard)
    }
}

private final class DropTargetView: FlippedView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var onDrop: ((NSPasteboard) -> Bool)?
    var onDragEntered: (() -> Void)?
    var onClick: (() -> Void)?
    var onDragging: ((Bool) -> Void)?
    var onMoved: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onMinimize: (() -> Void)?
    private var dragStart = NSPoint.zero
    private var dragWindowOrigin = NSPoint.zero
    private var moved = false
    private var docked = false
    private var dropArmed = false
    private var dropHover = false
    private var pasteHint = false
    private var caption = "灵感托盘"
    private var pendingCount = 0
    private var openProgress: CGFloat = 0
    private var openTarget: CGFloat = 0
    private var animation: Timer?
    private let minimize = AntButton("", kind: .text)
    var isPasteMode: Bool { pasteHint }

    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
            .fileURL, .URL, .png, .tiff, .string, .html, .rtf,
            NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType"),
            NSPasteboard.PasteboardType("Apple Web Archive pasteboard type"),
            NSPasteboard.PasteboardType("com.apple.webarchive"),
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.utf16-external-plain-text"),
            NSPasteboard.PasteboardType("public.text"),
            NSPasteboard.PasteboardType("public.plain-text"),
            NSPasteboard.PasteboardType("text/plain"),
            NSPasteboard.PasteboardType("com.apple.traditional-mac-plain-text"),
            NSPasteboard.PasteboardType("NSStringPboardType")
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.acceptedTypes)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityIdentifier("tray-folder")
        setAccessibilityLabel("灵感文件夹：点击查看素材，或拖入新素材")
        wantsLayer = true
        minimize.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        minimize.imagePosition = .imageOnly; minimize.toolTip = "收起到屏幕侧边"
        minimize.setAccessibilityLabel("收起灵感文件夹"); minimize.setAccessibilityIdentifier("tray-folder-minimize")
        minimize.target = self; minimize.action = #selector(minimizePressed)
        addSubview(minimize)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); minimize.frame = NSRect(x: bounds.width - 24, y: 2, width: 20, height: 20) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    @objc private func minimizePressed() { onMinimize?() }
    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation; dragWindowOrigin = window?.frame.origin ?? .zero
        moved = false; onDragging?(true); NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        let cursor = NSEvent.mouseLocation
        let dx = cursor.x - dragStart.x, dy = cursor.y - dragStart.y
        guard moved || abs(dx) + abs(dy) > 4 else { return }
        moved = true; window?.setFrameOrigin(NSPoint(x: dragWindowOrigin.x + dx, y: dragWindowOrigin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        NSCursor.pop(); onDragging?(false)
        if moved { onMoved?() } else { onClick?() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    func setSummary(project: String, pending: Int) {
        pendingCount = pending
        toolTip = "灵感托盘 · \(project)\n\(pending) 份待整理素材 · 点击查看全部素材；拖入收集，⌘V 粘贴"
        needsDisplay = true
    }
    func showEdgeHandle() {
        docked = true; dropArmed = false; dropHover = false; pasteHint = false
        caption = "灵感托盘"; minimize.isHidden = true; setOpen(false)
    }
    func showTrayAppearance(dragging: Bool = false) {
        docked = false; pasteHint = false; dropArmed = dragging
        caption = dragging ? "拖入收藏" : "灵感托盘"
        minimize.isHidden = false; setOpen(dragging)
    }
    func showPasteAppearance(isFocused: Bool = false) {
        docked = false; pasteHint = true; dropArmed = false
        caption = isFocused ? "⌘V 粘贴" : "已复制文字"
        minimize.isHidden = false; setOpen(isFocused)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?(); dropHover = true; caption = "松开放入"; setOpen(true); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHover = false; caption = dropArmed ? "拖入收藏" : "灵感托盘"; setOpen(dropArmed)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHover = false; return onDrop?(sender.draggingPasteboard) ?? false
    }
    private func setOpen(_ open: Bool) {
        let target: CGFloat = open ? 1 : 0
        guard target != openTarget || animation == nil && abs(openProgress - target) > 0.001 else { needsDisplay = true; return }
        animation?.invalidate(); animation = nil; openTarget = target
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { openProgress = target; needsDisplay = true; return }
        let start = openProgress, time = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - time) / 0.32)
            self.openProgress = start + (target - start) * CGFloat(1 - pow(1 - t, 3))
            self.needsDisplay = true
            if t >= 1 { timer.invalidate(); self.animation = nil }
        }
        animation = timer; RunLoop.main.add(timer, forMode: .common)
    }
    override func draw(_ dirtyRect: NSRect) {
        let p = openProgress, dx = (bounds.width - 104) / 2 - (docked ? 12 : 0)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: dx, yBy: 0); transform.concat()
        let back = NSBezierPath()
        back.move(to: NSPoint(x: 17, y: 24)); back.line(to: NSPoint(x: 17, y: 20))
        back.curve(to: NSPoint(x: 23, y: 14), controlPoint1: NSPoint(x: 17, y: 16), controlPoint2: NSPoint(x: 19, y: 14))
        back.line(to: NSPoint(x: 39, y: 14)); back.line(to: NSPoint(x: 47, y: 21))
        back.line(to: NSPoint(x: 82, y: 21))
        back.curve(to: NSPoint(x: 88, y: 27), controlPoint1: NSPoint(x: 86, y: 21), controlPoint2: NSPoint(x: 88, y: 23))
        back.line(to: NSPoint(x: 88, y: 62)); back.line(to: NSPoint(x: 17, y: 62)); back.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius = 8; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
        Palette.accentSoft.setFill(); back.fill(); NSGraphicsContext.restoreGraphicsState()
        Palette.accentBorder.setStroke(); back.lineWidth = 1; back.stroke()
        let inside = NSBezierPath(roundedRect: NSRect(x: 19, y: 28, width: 67, height: 34), xRadius: 4, yRadius: 4)
        Palette.accent.withAlphaComponent(0.16).setFill(); inside.fill()
        // Cards lift out as the front flap tips toward the user.
        for (x, offset) in [(CGFloat(25), CGFloat(0)), (CGFloat(31), CGFloat(5))] {
            let card = NSBezierPath(roundedRect: NSRect(x: x, y: 32 - p * (16 + offset), width: 46, height: 30), xRadius: 3, yRadius: 3)
            NSColor.white.setFill(); card.fill(); Palette.accentBorder.withAlphaComponent(0.7).setStroke(); card.lineWidth = 0.8; card.stroke()
            Palette.accent.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 7, y: 38 - p * (16 + offset), width: 24, height: 2), xRadius: 1, yRadius: 1).fill()
        }
        let left: CGFloat = 15 - 6 * p, right: CGFloat = 89 + 6 * p, top: CGFloat = 30 + 10 * p
        let front = NSBezierPath()
        front.move(to: NSPoint(x: left + 6, y: top)); front.line(to: NSPoint(x: right - 6, y: top))
        front.curve(to: NSPoint(x: right, y: top + 6), controlPoint1: NSPoint(x: right - 2, y: top), controlPoint2: NSPoint(x: right, y: top + 2))
        front.line(to: NSPoint(x: 85, y: 64))
        front.curve(to: NSPoint(x: 79, y: 70), controlPoint1: NSPoint(x: 84, y: 68), controlPoint2: NSPoint(x: 83, y: 70))
        front.line(to: NSPoint(x: 25, y: 70))
        front.curve(to: NSPoint(x: 19, y: 64), controlPoint1: NSPoint(x: 21, y: 70), controlPoint2: NSPoint(x: 20, y: 68))
        front.line(to: NSPoint(x: left, y: top + 6))
        front.curve(to: NSPoint(x: left + 6, y: top), controlPoint1: NSPoint(x: left, y: top + 2), controlPoint2: NSPoint(x: left + 2, y: top)); front.close()
        NSGradient(starting: .white, ending: dropHover ? Palette.accentSoft : NSColor(hex: 0xEDF5FF))?.draw(in: front, angle: 90)
        (dropHover ? Palette.accent : Palette.accentBorder).setStroke(); front.lineWidth = dropHover ? 1.5 : 1; front.stroke()
        let mark = NSBezierPath(); mark.lineWidth = 1.7; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
        if dropArmed || dropHover {
            mark.move(to: NSPoint(x: 52, y: 46)); mark.line(to: NSPoint(x: 52, y: 57))
            mark.move(to: NSPoint(x: 48, y: 53)); mark.line(to: NSPoint(x: 52, y: 57)); mark.line(to: NSPoint(x: 56, y: 53))
        } else {
            mark.move(to: NSPoint(x: 48, y: 51)); mark.line(to: NSPoint(x: 56, y: 51))
            mark.move(to: NSPoint(x: 52, y: 47)); mark.line(to: NSPoint(x: 52, y: 55))
        }
        Palette.accent.setStroke(); mark.stroke()
        if pendingCount > 0 && !docked {
            let text = pendingCount > 99 ? "99+" : String(pendingCount)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white]
            let size = (text as NSString).size(withAttributes: attrs)
            let badgeWidth = max(18, ceil(size.width) + 8)
            let badge = NSBezierPath(roundedRect: NSRect(x: 78, y: 29, width: badgeWidth, height: 18), xRadius: 9, yRadius: 9)
            Palette.accent.setFill(); badge.fill()
            (text as NSString).draw(at: NSPoint(x: 78 + (badgeWidth - size.width) / 2, y: 38 - size.height / 2), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        if !docked {
            let attrs: [NSAttributedString.Key: Any] = [.font: AntType.font(12, weight: .medium), .foregroundColor: dropArmed || pasteHint ? Palette.accent : Palette.secondary]
            let size = (caption as NSString).size(withAttributes: attrs)
            (caption as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 77), withAttributes: attrs)
        }
    }
}

private final class CanvasCardView: FlippedView {
    private let itemID: UUID
    private let preview = MaterialImageView()
    private let title = MaterialTitleField("")
    private let source = label("", size: AntType.caption, color: Palette.tertiary)

    init(card: CanvasCard) {
        itemID = card.item.id
        super.init(frame: .zero)
        rounded(self, color: Palette.panel, radius: AntMetrics.radiusLG, border: Palette.borderSecondary)
        elevate(self, level: 1)

        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.image = card.item.preview ?? NSImage(systemSymbolName: card.item.kind == "文字卡片" ? "text.quote" : "doc", accessibilityDescription: nil)
        rounded(preview, color: Palette.soft, radius: AntMetrics.radiusLG, border: Palette.borderSecondary)
        let type = label(card.item.kind, size: AntType.caption, color: Palette.accent)
        title.maximumNumberOfLines = 2
        source.maximumNumberOfLines = 1
        source.lineBreakMode = .byTruncatingTail
        updateMetadata(card.item)
        let note = label(card.note.isEmpty ? "未添加个人想法" : "“\(card.note)”", size: 14, weight: .medium)
        let location = label("\(card.project)  ·  \(card.location)", size: 12, weight: .medium, color: Palette.green)
        let tags = label(card.acceptedSuggestions.isEmpty ? "没有采纳 AI 标记" : "AI 标记 · " + card.acceptedSuggestions.joined(separator: " · "), size: 12, color: Palette.secondary)
        toolTip = card.suggestionEvidence.map { "\($0.label)\n依据：\($0.reason)" }.joined(separator: "\n\n")
        [preview, type, title, source, note, location, tags].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            preview.widthAnchor.constraint(equalToConstant: 72),
            preview.heightAnchor.constraint(equalToConstant: 72),
            type.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
            type.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            title.leadingAnchor.constraint(equalTo: type.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: type.bottomAnchor, constant: 5),
            source.leadingAnchor.constraint(equalTo: type.leadingAnchor),
            source.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            source.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            note.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 14),
            location.leadingAnchor.constraint(equalTo: note.leadingAnchor),
            location.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12),
            tags.leadingAnchor.constraint(equalTo: note.leadingAnchor),
            tags.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            tags.topAnchor.constraint(equalTo: location.bottomAnchor, constant: 7)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func updateMetadata(_ item: CaptureItem) {
        guard item.id == itemID else { return }
        title.stringValue = item.displayTitle
        source.stringValue = item.sourceSummary
        if let image = item.preview { preview.image = image }
        title.toolTip = item.displayTitle
        title.setAccessibilityLabel(item.displayTitle)
        title.onActivate = item.sourceURL == nil ? nil : { MaterialNavigation.open(item.sourceURL, browserBundleID: item.navigationBrowser) }
        if item.sourceURL != nil { title.toolTip = "返回来源：\(item.sourceURL!)" }
        preview.onActivate = {
            MaterialPreviewController.show(title: item.displayTitle, text: item.textContent, image: item.preview, sourceURL: item.sourceURL, originalURL: item.originalImageURL ?? (item.isImageURL ? item.sourceURL : nil), rendered: item.renderedPreview, browserBundleID: item.navigationBrowser)
        }
        preview.setAccessibilityElement(true)
        preview.setAccessibilityRole(.button)
        preview.setAccessibilityLabel(item.preview == nil ? "查看文字全文" : "放大图片")
    }
}

private final class CanvasController {
    private let context: CompanionContext
    let workspace: MacWorkspaceCanvas
    init(context: CompanionContext) { self.context = context; workspace = MacWorkspaceCanvas(context: context) }
    func add(_ card: CanvasCard) { reload(); show() }
    func reload() { workspace.reload() }
    func show() { workspace.show() }
    func showProjectHome() { workspace.show(projectHome: true) }
    func setCapturePresentation(_ active: Bool) { workspace.setCapturePresentation(active) }
    func updateMetadata(_ item: CaptureItem) {
        if let old = context.materials.first(where: { $0.id == item.id.uuidString }) {
            context.upsert(CompanionMaterial(id: old.id, project: old.project, title: item.displayTitle, text: item.textContent ?? old.text, note: old.note, area: old.area, image: item.preview ?? old.image, saved: old.saved, metadata: item.metadata(preserving: old.metadata)))
        }
        reload()
    }
    func memory(for project: String) -> [[String: String]] {
        context.materials.filter { $0.project == project && $0.saved }.suffix(8).map { ["id": $0.id, "title": $0.title, "note": $0.note, "area": $0.area] }
    }
}

private final class TrayContentsView: FlippedView {
    override var acceptsFirstResponder: Bool { true }
    var onPaste: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            onPaste?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    @objc func paste(_ sender: Any?) { onPaste?() }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes(DropTargetView.acceptedTypes) }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { layer?.borderColor = Palette.accent.cgColor; return .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { layer?.borderColor = Palette.borderSecondary.cgColor }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = Palette.borderSecondary.cgColor
        return onDrop?(sender.draggingPasteboard) ?? false
    }
}

// Harmony tray cards: bounded excerpts only; the material and its full preview remain unchanged.
private final class TrayMaterialRow: FlippedView {
    private let open: () -> Void
    private let preview = MaterialImageView()
    let cardHeight: CGFloat
    override var acceptsFirstResponder: Bool { true }
    init(_ material: CompanionMaterial, width: CGFloat = 187, open: @escaping () -> Void) {
        self.open = open
        let inner = width - 24
        func textHeight(_ value: String, size: CGFloat, lines: Int, inset: CGFloat = 0) -> CGFloat {
            let rect = (value as NSString).boundingRect(with: NSSize(width: inner - inset, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: size)])
            return min(CGFloat(lines) * ceil(size * 1.45), max(ceil(size * 1.45), ceil(rect.height) + 2))
        }
        let titleHeight = textHeight(material.title, size: 14, lines: 2)
        let bodyHeight = material.text.isEmpty ? 0 : textHeight(material.text, size: 12, lines: material.note.isEmpty ? 6 : 4)
        let noteHeight = material.note.isEmpty ? 0 : textHeight("我的批注 · " + material.note, size: 11, lines: 3, inset: 16) + 16
        let imageHeight: CGFloat = material.image.map { min(170, max(96, inner * $0.size.height / max(1, $0.size.width))) } ?? 0
        cardHeight = 24 + 16 + 8 + titleHeight + (imageHeight > 0 ? imageHeight + 8 : 0) + (bodyHeight > 0 ? bodyHeight + 8 : 0) + (noteHeight > 0 ? noteHeight + 8 : 0) + (material.metadata.generatedSuggestions.isEmpty ? 0 : 24) + 48
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: cardHeight))
        rounded(self, color: .white, radius: 12, border: Palette.borderSecondary)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityIdentifier("tray-material-" + material.id)
        setAccessibilityLabel(material.title + (material.saved ? "，已入画布" : "，待整理") + "，点击查看完整素材")
        toolTip = material.title + (material.note.isEmpty ? "" : "\n我的批注：" + material.note)
        func field(_ value: String, y: CGFloat, height: CGFloat, size: CGFloat, color: NSColor = Palette.secondary, lines: Int = 1, weight: NSFont.Weight = .regular) {
            let f = label(value, size: size, weight: weight, color: color)
            f.frame = NSRect(x: 12, y: y, width: inner, height: height)
            f.maximumNumberOfLines = lines; f.usesSingleLineMode = false; f.cell?.wraps = true; f.cell?.isScrollable = false; f.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingTail; f.cell?.truncatesLastVisibleLine = true
            addSubview(f)
        }
        let type = material.image != nil ? "▧ 图片" : material.metadata.sourceURL != nil ? "↗ 链接" : "Aa 文字"
        field(type, y: 12, height: 16, size: 11)
        let status = label(material.saved ? "已入画布" : "待整理", size: 11, color: material.saved ? Palette.accent : NSColor(hex: 0xA66A23))
        status.alignment = .right; status.frame = NSRect(x: width - 76, y: 12, width: 64, height: 16); addSubview(status)
        var y: CGFloat = 36
        field(material.title, y: y, height: titleHeight, size: 14, color: Palette.ink, lines: 2, weight: .medium); y += titleHeight + 8
        if let image = material.image {
            preview.image = image; preview.imageScaling = .scaleProportionallyUpOrDown
            preview.frame = NSRect(x: 12, y: y, width: inner, height: imageHeight)
            rounded(preview, color: Palette.soft, radius: 8)
            preview.setAccessibilityElement(true); preview.setAccessibilityRole(.button)
            preview.setAccessibilityIdentifier("tray-preview-" + material.id); preview.setAccessibilityLabel("放大图片")
            preview.onActivate = { MaterialPreviewController.show(title: material.title, text: material.text, image: material.image, sourceURL: material.metadata.sourceURL, originalURL: material.metadata.originalImageURL, rendered: material.metadata.renderedPreview, browserBundleID: material.metadata.browserBundleID) }
            addSubview(preview); y += imageHeight + 8
        }
        if bodyHeight > 0 { field(material.text, y: y, height: bodyHeight, size: 12, lines: material.note.isEmpty ? 6 : 4); y += bodyHeight + 8 }
        if noteHeight > 0 {
            let box = FlippedView(frame: NSRect(x: 12, y: y, width: inner, height: noteHeight)); rounded(box, color: NSColor(hex: 0xF2EDFA), radius: 7); addSubview(box)
            let note = label("我的批注 · " + material.note, size: 11, color: NSColor(hex: 0x7756A5)); note.frame = box.bounds.insetBy(dx: 8, dy: 8)
            note.maximumNumberOfLines = 3; note.usesSingleLineMode = false; note.cell?.wraps = true; note.cell?.isScrollable = false; note.lineBreakMode = .byWordWrapping; note.cell?.truncatesLastVisibleLine = true; box.addSubview(note); y += noteHeight + 8
        }
        if !material.metadata.generatedSuggestions.isEmpty { field("AI 建议 \(material.metadata.generatedSuggestions.count) · 已采纳 \(material.metadata.acceptedSuggestions.count)", y: y, height: 16, size: 11, color: Palette.accent); y += 24 }
        let source = CaptureItem(material: material)?.sourceSummary ?? material.metadata.source
        field(source.isEmpty ? "来源未记录" : source, y: y, height: 16, size: 11); y += 24
        field(material.project.isEmpty ? "未指定项目" : material.project + (material.area.isEmpty ? "" : " · " + material.area), y: y, height: 16, size: 11)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { open() } else { super.keyDown(with: event) }
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === preview || hit.isDescendant(of: preview) ? preview : self
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = Palette.soft.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = Palette.panel.cgColor }
    override func mouseDown(with event: NSEvent) { layer?.backgroundColor = Palette.accentSoft.cgColor }
    override func mouseUp(with event: NSEvent) { layer?.backgroundColor = Palette.panel.cgColor; if bounds.contains(convert(event.locationInWindow, from: nil)) { open() } }
    override func accessibilityPerformPress() -> Bool { open(); return true }
}

private final class TrayController: NSObject, NSTextFieldDelegate {
    private let panel: KeyPanel
    private let dropTarget = DropTargetView()
    private let canvas: CanvasController
    private var capturedItem: CaptureItem?
    private var sourceApp = "当前应用"
    private var noteField: NSTextField?
    private var projectPopup: NSPopUpButton?
    private var locationPopup: NSPopUpButton?
    private var suggestionButtons: [NSButton] = []
    private var previewRequests: [UUID: CapturePreviewRequest] = [:]
    private var browserRequests: [UUID: BrowserCaptureRequest] = [:]
    private var dragContext: BrowserDragContext?
    private var clipboardBrowserContext: BrowserDragContext?
    private let suggestionService: AgentAPIService
    private var suggestionData: [DesignSuggestion] = []
    private var suggestionTask: CompanionAgentRequest?
    private var suggestionWork: DispatchWorkItem?
    private var suggestionGeneration = UUID()
    private var lastSuggestionFingerprint: String?
    private var ocrCache: [UUID: String] = [:]
    private var ocrPending = Set<UUID>()
    private weak var suggestionStack: NSStackView?
    private weak var suggestionHint: NSTextField?
    private weak var suggestionRefresh: NSButton?
    private weak var summaryTitle: MaterialTitleField?
    private weak var summarySource: NSTextField?
    private weak var summaryImage: MaterialImageView?
    private weak var retryButton: NSButton?
    private weak var noteBodyButton: NSButton?
    private var summaryImageWidth: NSLayoutConstraint?
    private var summaryImageHeight: NSLayoutConstraint?
    private(set) var isExpanded = false
    private(set) var isDragging = false
    private var capturePresentation = false
    private var collectionQueueIDs: [String] = []
    var onDismissInCapture: (() -> Void)?
    private var pinnedTopLeft: NSPoint?
    private let folderSize = NSSize(width: 112, height: 96)
    private var folderAtEdge = true
    private var folderDocked = false
    private var folderHovered = false
    private var externalDragActive = false
    private var collapseWork: DispatchWorkItem?
    private var folderMonitor: Timer?
    private var suppressEdgeHover = false
    private var minimizedMaterialID: String?
    private var clipboardIntent = false
    private var isBrowsingContents = false
    private var minimizedContents = false
    private var contentsFilter = 0
    private weak var contentsHint: NSTextField?
    private var folderCenterY: CGFloat?
    private let positionDefaultsKey = "inspiration-tray-position"

    init(canvas: CanvasController, agent: AgentAPIService) {
        self.canvas = canvas
        self.suggestionService = agent
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 112),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        if let saved = UserDefaults.standard.dictionary(forKey: positionDefaultsKey), let x = saved["x"] as? Double, let y = saved["top"] as? Double, x.isFinite, y.isFinite {
            pinnedTopLeft = NSPoint(x: x, y: y)
        }
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.title = "灵感托盘"
        panel.setAccessibilityIdentifier("inspiration-tray-window")
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        dropTarget.onDrop = { [weak self] pasteboard in self?.receive(pasteboard, fromDrag: true) ?? false }
        dropTarget.onDragEntered = { [weak self] in
            guard let self else { return }
            self.externalDragActive = true; self.clipboardIntent = false; self.revealFromEdge()
        }
        dropTarget.onClick = { [weak self] in self?.showContents() }
        dropTarget.onHover = { [weak self] entered in self?.folderHoverChanged(entered) }
        dropTarget.onMinimize = { [weak self] in self?.armEdge() }
        dropTarget.onDragging = { [weak self] in self?.isDragging = $0 }
        dropTarget.onMoved = { [weak self] in self?.rememberPosition() }
        showCompactContent()
    }

    private func updateFolderSummary() {
        let context = suggestionService.context
        dropTarget.setSummary(project: context.project, pending: context.materials.filter { $0.project == context.project && !$0.saved }.count)
    }
    private func folderVisibleFrame() -> NSRect? {
        panel.screen?.visibleFrame ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.visibleFrame ?? NSScreen.main?.visibleFrame
    }
    func armEdge() {
        guard !isExpanded, !isDragging else { return }
        collapseWork?.cancel(); collapseWork = nil
        externalDragActive = false; folderAtEdge = true; folderDocked = true; folderHovered = false
        showCompactContent(); updateFolderSummary()
        guard let visible = folderVisibleFrame() else { return }
        dropTarget.showEdgeHandle(); panel.alphaValue = 1
        if panel.isKeyWindow { panel.makeFirstResponder(nil); panel.resignKey() }
        let center = min(max(visible.minY + 56, folderCenterY ?? visible.midY), visible.maxY - 56)
        folderCenterY = center
        let target = NSRect(x: visible.maxX - 32, y: center - folderSize.height / 2, width: folderSize.width, height: folderSize.height)
        suppressEdgeHover = target.contains(NSEvent.mouseLocation)
        panel.setFrame(target, display: true, animate: panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel.orderFrontRegardless(); monitorFolderPointer()
    }
    private func monitorFolderPointer() {
        guard folderMonitor == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] timer in
            guard let self, self.panel.isVisible, !self.isExpanded else { timer.invalidate(); self?.folderMonitor = nil; return }
            let inside = self.panel.frame.contains(NSEvent.mouseLocation)
            if self.folderDocked {
                if !inside { self.suppressEdgeHover = false; self.folderHovered = false }
                else if !self.suppressEdgeHover, !self.isDragging { self.folderHoverChanged(true) }
            } else if inside {
                if !self.folderHovered { self.folderHoverChanged(true) }
            } else if self.folderHovered || self.collapseWork == nil && !self.externalDragActive && !self.isDragging && !(self.panel.isKeyWindow && self.dropTarget.isPasteMode) {
                self.folderHoverChanged(false)
            }
        }
        folderMonitor = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func showFolder() {
        collapseWork?.cancel(); collapseWork = nil
        showCompactContent(); updateFolderSummary(); folderDocked = false; panel.alphaValue = 1
        if folderAtEdge, let visible = folderVisibleFrame() {
            let center = min(max(visible.minY + 56, folderCenterY ?? visible.midY), visible.maxY - 56)
            folderCenterY = center
            // Keep the outer edge under the hovering pointer as the folder slides out.
            panel.setFrame(NSRect(x: visible.maxX - folderSize.width, y: center - folderSize.height / 2, width: folderSize.width, height: folderSize.height), display: true, animate: panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } else { position(width: folderSize.width, height: folderSize.height) }
        panel.orderFrontRegardless(); monitorFolderPointer()
    }
    func showDropTarget(sourceApp: String, dragging: Bool = true) {
        guard !isExpanded, !isDragging else { return }
        self.sourceApp = sourceApp
        guard !externalDragActive else { return }
        externalDragActive = dragging; if dragging { clipboardIntent = false }; showFolder(); dropTarget.showTrayAppearance(dragging: dragging)
    }
    func setDragContext(_ context: BrowserDragContext?) {
        dragContext = context
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { sourceApp = app.localizedName ?? sourceApp }
    }
    func prepareForClipboardPaste(sourceApp: String, browserContext: BrowserDragContext? = nil) {
        self.sourceApp = sourceApp; clipboardBrowserContext = browserContext; clipboardIntent = true
        guard !isExpanded else { return }
        externalDragActive = false; showFolder(); dropTarget.showPasteAppearance()
    }
    private func folderHoverChanged(_ entered: Bool) {
        folderHovered = entered
        if entered {
            guard !folderDocked || !suppressEdgeHover else { return }
            collapseWork?.cancel(); collapseWork = nil
            if folderDocked { revealFromEdge() }
        } else {
            guard !isExpanded, !isDragging, !externalDragActive else { return }
            let work = DispatchWorkItem { [weak self] in self?.collapseWork = nil; self?.hideIfCompact() }
            collapseWork?.cancel(); collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
        }
    }
    func pasteFromClipboardIfFocused() -> Bool {
        guard panel.isKeyWindow else { return false }
        if isBrowsingContents { pasteIntoContents(); return true }
        guard !isExpanded, (panel.firstResponder as? NSTextView)?.isEditable != true else { return false }
        return receive(NSPasteboard.general)
    }

    func hideIfCompact() {
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        externalDragActive = false
        guard !isExpanded, !isDragging else { return }
        guard !(panel.isKeyWindow && dropTarget.isPasteMode) else { return }
        dropTarget.showTrayAppearance()
        guard !folderHovered else { return }
        armEdge()
    }
    func hideAll() {
        folderMonitor?.invalidate(); folderMonitor = nil
        collapseWork?.cancel(); collapseWork = nil; minimizedMaterialID = nil; minimizedContents = false; clipboardIntent = false
        externalDragActive = false
        if isExpanded { updateSharedMaterial() }
        cancelCurrentPreview(); capturedItem = nil; collectionQueueIDs.removeAll()
        isExpanded = false; panel.orderOut(nil)
    }
    func setCapturePresentation(_ active: Bool) {
        capturePresentation = active
        panel.level = NSWindow.Level(rawValue: active ? NSWindow.Level.screenSaver.rawValue + 5 : NSWindow.Level.statusBar.rawValue + 1)
    }
    private func showCompactContent() {
        panel.hasShadow = false
        isExpanded = false; isBrowsingContents = false; setCapturePresentation(capturePresentation)
        if panel.contentView !== dropTarget { panel.contentView = dropTarget }
    }
    private func revealFromEdge() {
        guard !isExpanded else { return }
        sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? sourceApp
        if !externalDragActive, !clipboardIntent, minimizedContents { showContents(); return }
        if !externalDragActive, !clipboardIntent, let id = minimizedMaterialID,
           suggestionService.context.materials.contains(where: { $0.id == id && $0.project == suggestionService.context.project }) {
            minimizedMaterialID = nil; openMaterial(id); return
        }
        showFolder()
        if clipboardIntent, !externalDragActive { dropTarget.showPasteAppearance() }
        else { dropTarget.showTrayAppearance(dragging: externalDragActive) }
    }
    private func rememberClipboardSource() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        sourceApp = app.localizedName ?? sourceApp
        if let bundle = app.bundleIdentifier, BrowserCaptureRequest.supportedBrowsers.contains(bundle) {
            let point = NSEvent.mouseLocation
            clipboardBrowserContext = BrowserDragContext(bundleID: bundle, processID: app.processIdentifier, screenPoint: CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y))
        } else { clipboardBrowserContext = nil }
    }
    @objc private func pasteIntoContents() {
        if !receive(NSPasteboard.general) { contentsHint?.stringValue = "剪贴板中没有可收集的内容"; NSSound.beep() }
    }
    @objc private func contentsFilterChanged(_ sender: NSSegmentedControl) {
        contentsFilter = sender.selectedSegment; showContents()
    }
    @objc func showContents() {
        rememberClipboardSource(); panel.makeFirstResponder(nil)
        if isExpanded { updateSharedMaterial() }
        cancelCurrentPreview(); capturedItem = nil
        folderMonitor?.invalidate(); folderMonitor = nil; collapseWork?.cancel(); collapseWork = nil
        minimizedMaterialID = nil; minimizedContents = false; externalDragActive = false; clipboardIntent = false
        isExpanded = true; isBrowsingContents = true; panel.hasShadow = true; panel.alphaValue = 1
        setCapturePresentation(capturePresentation)
        let context = suggestionService.context
        let all = context.materials.filter { $0.project == context.project }.reversed()
        let pendingCount = all.filter { !$0.saved }.count
        let materials = all.filter { contentsFilter == 0 || (contentsFilter == 1 ? !$0.saved : $0.saved) }
        let root = TrayContentsView(); root.onDrop = { [weak self] in self?.receive($0, fromDrag: true) ?? false }; root.onPaste = { [weak self] in self?.pasteIntoContents() }; root.setAccessibilityIdentifier("tray-contents"); root.setAccessibilityElement(true); root.setAccessibilityRole(.group); root.setAccessibilityLabel("托盘素材列表")
        rounded(root, color: NSColor(hex: 0xF7F8FA), radius: AntMetrics.radiusXL, border: Palette.borderSecondary); elevate(root, level: 3)
        let header = TrayHeaderDragView()
        header.onDragging = { [weak self] in self?.isDragging = $0 }; header.onMoved = { [weak self] in self?.rememberPosition() }
        header.toolTip = "拖动标题栏移动灵感托盘"
        let title = label("灵感托盘", size: AntType.heading, weight: .semibold)
        let subtitle = label("\(context.project) · \(all.count) 份素材 · \(pendingCount) 份待整理", size: AntType.caption, color: Palette.secondary)
        subtitle.lineBreakMode = .byTruncatingTail
        let icon = NSImageView(); icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil); icon.contentTintColor = Palette.accent
        rounded(icon, color: Palette.accentSoft, radius: AntMetrics.radiusLG)
        let minimize = AntButton("", kind: .text, target: self, action: #selector(minimizeExpanded))
        minimize.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil); minimize.imagePosition = .imageOnly
        minimize.toolTip = "收起到侧边，悬停恢复列表"; minimize.setAccessibilityLabel("收起灵感托盘"); minimize.setAccessibilityIdentifier("tray-minimize")
        let close = AntButton("×", kind: .text, target: self, action: #selector(closeExpanded)); close.setAccessibilityIdentifier("tray-close"); close.toolTip = "关闭托盘"
        close.font = .systemFont(ofSize: 18)
        [icon, title, subtitle, minimize, close].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; header.addSubview($0) }
        let filters = NSSegmentedControl(labels: ["全部 \(all.count)", "待整理 \(pendingCount)", "已入画布 \(all.count - pendingCount)"], trackingMode: .selectOne, target: self, action: #selector(contentsFilterChanged(_:)))
        filters.font = AntType.font(AntType.caption); filters.selectedSegment = contentsFilter; filters.segmentStyle = .rounded
        filters.setAccessibilityIdentifier("tray-contents-filter")
        let scroll = NSScrollView(); scroll.scrollerStyle = .overlay; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let document = FlippedView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        // Match Harmony WaterFlow: shortest column first, 12pt gutter and a reserved scrollbar lane.
        let cardWidth: CGFloat = 187
        var columnBottoms: [CGFloat] = [0, 0]
        for material in materials {
            let column = columnBottoms[0] <= columnBottoms[1] ? 0 : 1
            let card = TrayMaterialRow(material, width: cardWidth) { [weak self] in self?.openMaterial(material.id) }
            card.frame.origin = NSPoint(x: CGFloat(column) * (cardWidth + 12), y: columnBottoms[column])
            document.addSubview(card); columnBottoms[column] += card.cardHeight + 10
        }
        let contentHeight = max(260, (columnBottoms.max() ?? 0) - 10)
        if materials.isEmpty {
            let empty = FlippedView(frame: NSRect(x: 0, y: 0, width: 386, height: contentHeight))
            empty.setAccessibilityIdentifier("tray-contents-empty"); empty.setAccessibilityElement(true); empty.setAccessibilityRole(.group)
            let heading = label(all.isEmpty ? "先收集，不急着整理" : contentsFilter == 1 ? "待整理素材已清空" : "还没有放入画布的素材", size: 16, weight: .medium, color: Palette.ink)
            let hint = label(all.isEmpty ? "拖入图片或文字，或按 ⌘V 粘贴素材。" : "切换上方分类查看其他素材", size: 12, color: Palette.secondary)
            heading.alignment = .center; hint.alignment = .center
            heading.frame = NSRect(x: 8, y: 94, width: 370, height: 24); hint.frame = NSRect(x: 8, y: 130, width: 370, height: 24)
            empty.addSubview(heading); empty.addSubview(hint); document.addSubview(empty)
        }
        let paste = AntButton("粘贴素材", kind: .secondary, target: self, action: #selector(pasteIntoContents))
        paste.toolTip = "将剪贴板内容收集到托盘（⌘V）"; paste.setAccessibilityIdentifier("tray-paste")
        let collect = AntButton("继续收集", kind: .primary, target: self, action: #selector(continueCollecting)); collect.setAccessibilityIdentifier("tray-collect-more")
        let hint = label("⌘V 粘贴", size: AntType.caption, color: Palette.tertiary); contentsHint = hint
        [header, filters, scroll, paste, collect, hint].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 430),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor), header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.topAnchor.constraint(equalTo: root.topAnchor), header.heightAnchor.constraint(equalToConstant: 68),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16), icon.topAnchor.constraint(equalTo: header.topAnchor, constant: 16), icon.widthAnchor.constraint(equalToConstant: 32), icon.heightAnchor.constraint(equalToConstant: 32),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), title.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3), subtitle.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12), close.topAnchor.constraint(equalTo: header.topAnchor, constant: 12), close.widthAnchor.constraint(equalToConstant: 32), close.heightAnchor.constraint(equalToConstant: 32),
            minimize.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -2), minimize.centerYAnchor.constraint(equalTo: close.centerYAnchor), minimize.widthAnchor.constraint(equalToConstant: 28), minimize.heightAnchor.constraint(equalToConstant: 32),
            title.trailingAnchor.constraint(lessThanOrEqualTo: minimize.leadingAnchor, constant: -8),
            filters.topAnchor.constraint(equalTo: root.topAnchor, constant: 76), filters.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), filters.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), filters.heightAnchor.constraint(equalToConstant: 32),
            scroll.topAnchor.constraint(equalTo: filters.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: filters.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: filters.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: paste.topAnchor, constant: -12),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), document.heightAnchor.constraint(equalToConstant: contentHeight),
            paste.leadingAnchor.constraint(equalTo: filters.leadingAnchor), paste.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16), paste.widthAnchor.constraint(equalToConstant: 96), paste.heightAnchor.constraint(equalToConstant: 32),
            hint.leadingAnchor.constraint(equalTo: paste.trailingAnchor, constant: 8), hint.centerYAnchor.constraint(equalTo: paste.centerYAnchor), hint.trailingAnchor.constraint(lessThanOrEqualTo: collect.leadingAnchor, constant: -8),
            collect.trailingAnchor.constraint(equalTo: filters.trailingAnchor), collect.bottomAnchor.constraint(equalTo: paste.bottomAnchor), collect.widthAnchor.constraint(equalToConstant: 104), collect.heightAnchor.constraint(equalTo: paste.heightAnchor)
        ])
        panel.contentView = root
        position(width: 430, height: max(440, min(680, 180 + contentHeight)))
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(root)
    }

    private func receive(_ pasteboard: NSPasteboard, fromDrag: Bool = false) -> Bool {
        guard var item = PasteboardReader.read(pasteboard, sourceApp: sourceApp) else { return false }
        clipboardIntent = false
        if isExpanded { updateSharedMaterial() }
        cancelCurrentPreview()
        if fromDrag, let context = dragContext, Date().timeIntervalSince(context.startedAt) < 60 { item.browserContext = context }
        if !fromDrag, item.kind == "文字卡片" || item.siteName != nil { item.browserContext = clipboardBrowserContext }
        item.isLoadingPreview = item.siteName != nil && (item.needsWebTitle || item.preview == nil || item.isPageReference && item.browserContext != nil && !item.hasNoteBody)
        capturedItem = item
        showExpanded(item)
        updateSharedMaterial()
        if item.isLoadingPreview { resolveContent(item) }
        if !item.isLoadingPreview { scheduleSuggestions() }
        if item.kind == "文字卡片", let context = item.browserContext, let text = item.textContent {
            BrowserTextSource.read(context: context, expectedText: text) { [weak self] url in
                guard let self, let url else { return }
                var updated = self.capturedItem?.id == item.id ? self.capturedItem! : item
                updated.sourceURL = url
                self.updatePreview(updated)
            }
        }
        return true
    }

    @discardableResult func resumePending() -> Bool {
        guard let material = suggestionService.context.materials.last(where: { $0.project == suggestionService.context.project && !$0.saved }) else { return false }
        openMaterial(material.id); return true
    }
    func showCollection(_ ids: [String]) {
        collectionQueueIDs = ids
        let items = suggestionService.context.materials.filter { ids.contains($0.id) }
        if let first = items.first(where: { $0.image != nil }) ?? items.first { openMaterial(first.id) }
    }
    @objc private func pendingMaterialChanged(_ sender: NSPopUpButton) {
        if let id = sender.selectedItem?.representedObject as? String { openMaterial(id) }
    }
    func openMaterial(_ id: String) {
        if isExpanded { updateSharedMaterial() }
        cancelCurrentPreview()
        guard let material = suggestionService.context.materials.first(where: { $0.id == id }), let item = CaptureItem(material: material) else { return }
        if !capturePresentation || material.project == suggestionService.context.project { suggestionService.context.setProject(material.project, area: material.area) }
        capturedItem = item
        if item.textSource == "image_ocr" { ocrCache[item.id] = material.text }
        showExpanded(item)
        noteField?.stringValue = material.note
        projectPopup?.selectItem(withTitle: material.project); locationPopup?.selectItem(withTitle: material.area)
        suggestionHint?.stringValue = item.evidenceSummary + " · 已恢复"
        suggestionRefresh?.isEnabled = true
        if material.metadata.generatedSuggestions.isEmpty { showSuggestionStatus("素材与想法已恢复，可点击「重新生成」请求建议。") }
        else { showSuggestions(material.metadata.generatedSuggestions, accepted: material.metadata.acceptedSuggestions) }
    }

    private func cancelCurrentPreview() {
        cancelSuggestions()
        guard let id = capturedItem?.id else { return }
        previewRequests.removeValue(forKey: id)?.cancel()
        browserRequests.removeValue(forKey: id)?.cancel()
    }

    private func resolveContent(_ item: CaptureItem) {
        guard let context = item.browserContext, let url = item.sourceURL.flatMap(URL.init(string:)) else {
            resolvePreview(item)
            return
        }
        let request = BrowserCaptureRequest()
        browserRequests[item.id] = request
        request.start(url: url, context: context) { [weak self] result in
            guard let self else { return }
            self.browserRequests.removeValue(forKey: item.id)
            guard (result.matched && (result.title != nil || result.image != nil || result.text != nil)) || result.hint != nil else {
                self.resolvePreview(item)
                return
            }
            var updated = item
            if let title = result.title { updated.title = title }
            if updated.preview == nil { updated.preview = result.image }
            if let source = result.sourceURL { updated.sourceURL = source }
            if let text = result.text, !text.isEmpty {
                updated.textContent = text; updated.textSource = result.textSource; updated.textTruncated = result.textTruncated
            }
            updated.originalImageURL = result.imageURL
            updated.renderedPreview = result.rendered
            updated.fromBrowserPage = result.matched
            updated.browserHint = result.hint
            if updated.preview != nil && !updated.needsWebTitle && (!updated.isPageReference || updated.hasNoteBody) { updated.browserHint = nil }
            if updated.isPageReference && !updated.hasNoteBody && updated.browserHint == nil {
                updated.browserHint = "尚未读取笔记正文；请在来源浏览器打开这篇笔记详情，再点重试。摘要、封面和 OCR 不代表完整笔记。"
            }
            updated.isLoadingPreview = false
            updated.previewFailed = updated.browserHint != nil
            self.updatePreview(updated)
        }
    }

    private func updatePreview(_ resolved: CaptureItem) {
        if isExpanded, capturedItem?.id == resolved.id {
            capturedItem = resolved
            configureActions(resolved)
            summaryTitle?.stringValue = resolved.displayTitle
            summaryTitle?.toolTip = resolved.displayTitle
            summarySource?.stringValue = resolved.sourceSummary
            summarySource?.toolTip = [resolved.evidenceSummary, resolved.browserHint, resolved.sourceURL].compactMap { $0 }.joined(separator: "\n")
            if let image = resolved.preview {
                summaryImage?.image = image
                summaryImage?.contentTintColor = nil
                summaryImageWidth?.constant = 64
                summaryImageHeight?.constant = 64
            }
            retryButton?.isHidden = !resolved.previewFailed
            retryButton?.toolTip = resolved.browserHint ?? "重新读取素材预览"
        }
        canvas.updateMetadata(resolved)
        if isExpanded, capturedItem?.id == resolved.id, !resolved.isLoadingPreview { scheduleSuggestions() }
    }

    private func resolvePreview(_ initial: CaptureItem) {
        guard let url = initial.sourceURL.flatMap(URL.init(string:)) else { return }
        var resolved = initial
        let request = CapturePreviewRequest { [weak self] update in
            guard let self else { return }
            if let title = update.title, resolved.needsWebTitle { resolved.title = title }
            if let image = update.image, resolved.preview == nil { resolved.preview = image }
            resolved.isLoadingPreview = !update.finished
            resolved.previewFailed = update.failed
            self.updatePreview(resolved)
            if update.finished { self.previewRequests.removeValue(forKey: initial.id) }
        }
        previewRequests[initial.id] = request
        request.start(url: url, imageURL: initial.isImageURL)
    }

    @objc private func showNoteBody() {
        guard let item = capturedItem, let text = item.textContent, !text.isEmpty else { return }
        MaterialPreviewController.show(title: item.displayTitle + " · 采集正文", text: text, image: nil, sourceURL: item.sourceURL, originalURL: nil, rendered: false, browserBundleID: item.navigationBrowser)
    }
    private func restoreBrowserContext(_ item: inout CaptureItem) {
        guard item.browserContext == nil, let bundle = item.navigationBrowser, BrowserCaptureRequest.supportedBrowsers.contains(bundle),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return }
        item.browserContext = BrowserDragContext(bundleID: bundle, processID: app.processIdentifier, screenPoint: CGPoint(x: -1000, y: -1000))
    }
    @objc private func retryPreview() {
        guard var item = capturedItem, !item.isLoadingPreview else { return }
        restoreBrowserContext(&item)
        cancelSuggestions()
        item.isLoadingPreview = true
        item.previewFailed = false
        item.browserHint = nil
        capturedItem = item
        summaryTitle?.stringValue = item.displayTitle
        summarySource?.stringValue = item.sourceSummary
        retryButton?.isHidden = true
        resolveContent(item)
    }

    private func showExpanded(_ item: CaptureItem) {
        folderMonitor?.invalidate(); folderMonitor = nil
        collapseWork?.cancel(); collapseWork = nil; minimizedMaterialID = nil; externalDragActive = false
        isExpanded = true; isBrowsingContents = false; minimizedContents = false; panel.hasShadow = true
        setCapturePresentation(capturePresentation)
        panel.alphaValue = 1
        let root = FlippedView()
        rounded(root, color: Palette.panel, radius: AntMetrics.radiusXL, border: Palette.borderSecondary)
        elevate(root, level: 3)
        panel.contentView = root

        let dragHeader = TrayHeaderDragView()
        dragHeader.toolTip = "拖动标题栏移动灵感托盘"
        dragHeader.onDragging = { [weak self] in self?.isDragging = $0 }
        dragHeader.onMoved = { [weak self] in self?.rememberPosition() }
        dragHeader.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dragHeader)

        let headerIcon = AntButton("", kind: .text, target: self, action: #selector(showContents))
        headerIcon.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil); headerIcon.imagePosition = .imageOnly
        headerIcon.toolTip = "返回素材列表"; headerIcon.setAccessibilityLabel("返回素材列表"); headerIcon.setAccessibilityIdentifier("tray-back")
        let header = label("素材详情", size: AntType.heading, weight: .semibold)
        let status = label("原文、批注与 AI 建议分开保留", size: AntType.caption, color: Palette.secondary)
        let pending = AntSelect()
        var candidates = suggestionService.context.materials.filter { (!$0.saved && $0.project == suggestionService.context.project) || collectionQueueIDs.contains($0.id) }
        if !candidates.contains(where: { $0.id == item.id.uuidString }) {
            candidates.append(CompanionMaterial(id: item.id.uuidString, project: suggestionService.context.project, title: item.displayTitle, text: item.textContent ?? "", note: "", area: suggestionService.context.area, image: item.preview, saved: false))
        }
        for (index, material) in candidates.enumerated() {
            pending.addItem(withTitle: "\(index + 1) · " + material.title)
            pending.lastItem?.representedObject = material.id
            if material.id == item.id.uuidString { pending.selectItem(at: index) }
        }
        pending.target = self; pending.action = #selector(pendingMaterialChanged(_:))
        pending.setAccessibilityLabel("切换托盘素材")
        pending.setAccessibilityIdentifier("tray-material-picker")
        pending.toolTip = "本批 \(candidates.count) 份素材，可逐张添加想法和选择保存位置"
        let minimize = AntButton("", kind: .text, target: self, action: #selector(minimizeExpanded))
        minimize.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
        minimize.imagePosition = .imageOnly; minimize.toolTip = "收起到侧边，悬停恢复"
        minimize.setAccessibilityLabel("收起灵感托盘"); minimize.setAccessibilityIdentifier("tray-minimize")
        let close = AntButton("×", kind: .text, target: self, action: #selector(closeExpanded))
        close.setAccessibilityIdentifier("tray-close")
        close.font = .systemFont(ofSize: 18, weight: .medium)

        let previewContainer = FlippedView()
        let thumbnail = NSView()
        rounded(thumbnail, color: item.siteName == nil ? Palette.soft : Palette.accentSoft, radius: AntMetrics.radiusLG)
        let preview = MaterialImageView()
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.image = item.preview ?? NSImage(systemSymbolName: item.siteName != nil ? "link" : item.kind == "文字卡片" ? "text.quote" : "doc", accessibilityDescription: item.kind)
        preview.contentTintColor = item.siteName == nil ? Palette.secondary : Palette.accent
        if item.preview != nil { preview.contentTintColor = nil }
        let itemTitle = MaterialTitleField(item.displayTitle)
        let source = label(item.sourceSummary, size: AntType.caption, color: Palette.tertiary)
        previewContainer.toolTip = item.sourceURL ?? item.source
        itemTitle.toolTip = item.displayTitle
        [itemTitle, source].forEach { field in
            field.maximumNumberOfLines = field === itemTitle ? 2 : 1
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        [thumbnail, itemTitle, source].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; previewContainer.addSubview($0) }
        preview.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.addSubview(preview)
        thumbnail.layer?.masksToBounds = true
        let retry = AntButton("重试", kind: .text, target: self, action: #selector(retryPreview))
        retry.font = AntType.font(AntType.caption)
        retry.isHidden = !item.previewFailed
        retry.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(retry)
        summaryTitle = itemTitle
        summarySource = source
        summaryImage = preview
        retryButton = retry
        let bodyButton = AntButton("正文", kind: .text, target: self, action: #selector(showNoteBody))
        bodyButton.font = AntType.font(AntType.caption); bodyButton.setAccessibilityIdentifier("tray-note-body"); bodyButton.setAccessibilityLabel("查看采集正文")
        bodyButton.translatesAutoresizingMaskIntoConstraints = false; previewContainer.addSubview(bodyButton); noteBodyButton = bodyButton
        summaryImageWidth = preview.widthAnchor.constraint(equalToConstant: item.preview == nil ? 20 : 64)
        summaryImageHeight = preview.heightAnchor.constraint(equalToConstant: item.preview == nil ? 20 : 64)
        configureActions(item)
        let divider = NSView()
        rounded(divider, color: Palette.borderSecondary, radius: 0)

        let noteTitle = label("我的批注", size: AntType.caption, color: Palette.secondary)
        let note = AntInput()
        note.cell = AntInputCell(textCell: "")
        note.isEditable = true
        note.isSelectable = true
        note.placeholderString = "补充想法，原文不会被覆盖"
        styleInput(note)
        note.delegate = self
        note.setAccessibilityIdentifier("tray-note")
        noteField = note

        let destinationTitle = label("保存到", size: AntType.caption, color: Palette.secondary)
        let project = AntSelect()
        project.addItems(withTitles: suggestionService.context.projectNames)
        project.selectItem(withTitle: suggestionService.context.project)
        project.target = self
        project.action = #selector(suggestionContextChanged)
        projectPopup = project
        let location = AntSelect()
        location.addItems(withTitles: Array(Set(["标题排版探索区", "色彩与质感区", "待整理收集区", suggestionService.context.area])).sorted())
        location.selectItem(withTitle: suggestionService.context.area)
        location.target = self
        location.action = #selector(suggestionContextChanged)
        locationPopup = location

        let aiContainer = FlippedView()
        rounded(aiContainer, color: Palette.accentSoft, radius: AntMetrics.radiusLG, border: Palette.accentBorder)
        let aiBadge = label("✦  AI 建议 · 与原文分开", size: AntType.body, weight: .semibold, color: Palette.accent)
        let aiHint = label("基于素材文字 / OCR；勾选后采纳", size: AntType.caption, color: Palette.secondary)
        aiHint.maximumNumberOfLines = 1
        aiHint.lineBreakMode = .byTruncatingTail
        let refresh = AntButton("重新生成", kind: .text, target: self, action: #selector(refreshSuggestions))
        refresh.font = AntType.font(AntType.caption)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        suggestionStack = stack
        suggestionHint = aiHint
        suggestionRefresh = refresh
        suggestionButtons = []
        suggestionData = []
        [aiBadge, aiHint, refresh, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; aiContainer.addSubview($0) }
        showSuggestionStatus(item.isLoadingPreview ? "正在读取素材，随后生成建议…" : "正在准备 AI 建议…")

        let continueButton = AntButton("继续收集", kind: .secondary, target: self, action: #selector(continueCollecting))
        let addButton = AntButton("放入画布  →", kind: .primary, target: self, action: #selector(addToCanvas))
        addButton.keyEquivalent = "\r"
        [headerIcon, header, status, pending, minimize, close].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            dragHeader.addSubview($0)
        }
        [previewContainer, divider, noteTitle, note, destinationTitle, project, location, aiContainer, continueButton, addButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        let constraints: [NSLayoutConstraint] = [
            root.widthAnchor.constraint(equalToConstant: 430),
            dragHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dragHeader.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            dragHeader.topAnchor.constraint(equalTo: root.topAnchor),
            dragHeader.heightAnchor.constraint(equalToConstant: 64),
            headerIcon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            headerIcon.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            headerIcon.widthAnchor.constraint(equalToConstant: 32),
            headerIcon.heightAnchor.constraint(equalToConstant: 32),
            header.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 12),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            status.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            status.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: headerIcon.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 32),
            close.heightAnchor.constraint(equalToConstant: 32),
            minimize.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -2), minimize.centerYAnchor.constraint(equalTo: headerIcon.centerYAnchor), minimize.widthAnchor.constraint(equalToConstant: 28), minimize.heightAnchor.constraint(equalToConstant: 32),
            pending.trailingAnchor.constraint(equalTo: minimize.leadingAnchor, constant: -4), pending.centerYAnchor.constraint(equalTo: headerIcon.centerYAnchor), pending.widthAnchor.constraint(equalToConstant: 96), pending.heightAnchor.constraint(equalToConstant: 32),
            previewContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            previewContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            previewContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 72),
            previewContainer.heightAnchor.constraint(equalToConstant: 84),
            thumbnail.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            thumbnail.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 4),
            thumbnail.widthAnchor.constraint(equalToConstant: 64),
            thumbnail.heightAnchor.constraint(equalToConstant: 64),
            preview.centerXAnchor.constraint(equalTo: thumbnail.centerXAnchor),
            preview.centerYAnchor.constraint(equalTo: thumbnail.centerYAnchor),
            summaryImageHeight!,
            summaryImageWidth!,
            itemTitle.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12),
            itemTitle.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            itemTitle.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 4),
            source.leadingAnchor.constraint(equalTo: itemTitle.leadingAnchor),
            source.trailingAnchor.constraint(equalTo: bodyButton.leadingAnchor, constant: -4),
            bodyButton.trailingAnchor.constraint(equalTo: retry.leadingAnchor, constant: -4), bodyButton.centerYAnchor.constraint(equalTo: source.centerYAnchor), bodyButton.widthAnchor.constraint(equalToConstant: 32), bodyButton.heightAnchor.constraint(equalToConstant: 24),
            source.topAnchor.constraint(equalTo: itemTitle.bottomAnchor, constant: 4),
            retry.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            retry.centerYAnchor.constraint(equalTo: source.centerYAnchor),
            retry.widthAnchor.constraint(equalToConstant: 32),
            retry.heightAnchor.constraint(equalToConstant: 24),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            divider.topAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            noteTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            noteTitle.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 16),
            note.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            note.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            note.topAnchor.constraint(equalTo: noteTitle.bottomAnchor, constant: 8),
            note.heightAnchor.constraint(equalToConstant: 36),
            destinationTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            destinationTitle.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 16),
            project.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            project.topAnchor.constraint(equalTo: destinationTitle.bottomAnchor, constant: 8),
            project.widthAnchor.constraint(equalTo: location.widthAnchor),
            project.heightAnchor.constraint(equalToConstant: AntMetrics.control),
            location.leadingAnchor.constraint(equalTo: project.trailingAnchor, constant: 8),
            location.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            location.centerYAnchor.constraint(equalTo: project.centerYAnchor),
            location.heightAnchor.constraint(equalToConstant: AntMetrics.control),
            aiContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            aiContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            aiContainer.topAnchor.constraint(equalTo: project.bottomAnchor, constant: 16),
            aiContainer.heightAnchor.constraint(equalToConstant: 160),
            aiBadge.leadingAnchor.constraint(equalTo: aiContainer.leadingAnchor, constant: 12),
            aiBadge.topAnchor.constraint(equalTo: aiContainer.topAnchor, constant: 12),
            aiHint.leadingAnchor.constraint(equalTo: aiBadge.leadingAnchor),
            aiHint.topAnchor.constraint(equalTo: aiBadge.bottomAnchor, constant: 4),
            aiHint.trailingAnchor.constraint(equalTo: aiContainer.trailingAnchor, constant: -12),
            refresh.trailingAnchor.constraint(equalTo: aiContainer.trailingAnchor, constant: -8),
            refresh.centerYAnchor.constraint(equalTo: aiBadge.centerYAnchor),
            refresh.widthAnchor.constraint(equalToConstant: 72), refresh.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: aiBadge.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: aiContainer.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: aiHint.bottomAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: aiContainer.bottomAnchor, constant: -8),
            continueButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            continueButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            continueButton.widthAnchor.constraint(equalToConstant: 104),
            continueButton.heightAnchor.constraint(equalToConstant: AntMetrics.control),
            addButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            addButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            addButton.widthAnchor.constraint(equalToConstant: 132),
            addButton.heightAnchor.constraint(equalToConstant: AntMetrics.control)
        ]
        NSLayoutConstraint.activate(constraints)
        position(width: 430, height: 544)
        panel.makeKeyAndOrderFront(nil)
    }

    private func configureActions(_ item: CaptureItem) {
        noteBodyButton?.isHidden = (item.textContent ?? "").isEmpty || item.textSource == "image_ocr"
        noteBodyButton?.title = item.isPageReference && !item.hasNoteBody ? "摘要" : "正文"
        summarySource?.toolTip = [item.evidenceSummary, item.browserHint, item.sourceURL].compactMap { $0 }.joined(separator: "\n")
        noteBodyButton?.toolTip = item.evidenceSummary
        summaryTitle?.setAccessibilityLabel(item.displayTitle)
        summaryTitle?.onActivate = item.sourceURL == nil ? nil : { MaterialNavigation.open(item.sourceURL, browserBundleID: item.navigationBrowser) }
        summaryTitle?.toolTip = item.sourceURL.map { "返回来源：\($0)" } ?? item.displayTitle
        summaryImage?.onActivate = {
            MaterialPreviewController.show(title: item.displayTitle, text: item.textContent, image: item.preview, sourceURL: item.sourceURL, originalURL: item.originalImageURL ?? (item.isImageURL ? item.sourceURL : nil), rendered: item.renderedPreview, browserBundleID: item.navigationBrowser)
        }
        summaryImage?.setAccessibilityElement(true)
        summaryImage?.setAccessibilityRole(.button)
        summaryImage?.setAccessibilityLabel(item.preview == nil ? "查看文字全文" : "放大图片")
    }

    private func cancelSuggestions() {
        suggestionWork?.cancel()
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestionGeneration = UUID()
        lastSuggestionFingerprint = nil
    }

    private func showSuggestionStatus(_ text: String) {
        guard let stack = suggestionStack else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        suggestionButtons = []
        suggestionData = []
        let status = label(text, size: AntType.caption, color: Palette.secondary)
        status.maximumNumberOfLines = 3
        status.toolTip = text
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func scheduleSuggestions(force: Bool = false) {
        guard isExpanded, let item = capturedItem else { return }
        updateSharedMaterial()
        guard !item.isLoadingPreview else { return }
        if let material = suggestionService.context.materials.first(where: { $0.id == item.id.uuidString }),
           let origin = material.metadata.originCaptureAssetID,
           let asset = suggestionService.context.assets.first(where: { $0.id == origin }) {
            if asset.preparing {
                suggestionWork?.cancel(); showSuggestionStatus("正在读取圈选内容…")
                let wait = DispatchWorkItem { [weak self] in self?.scheduleSuggestions(force: force) }; suggestionWork = wait
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: wait); return
            }
            ocrCache[item.id] = asset.text
        }
        if suggestionService.context.isPreparing {
            suggestionWork?.cancel()
            showSuggestionStatus("正在识别共享圈选中的文字…")
            let wait = DispatchWorkItem { [weak self] in self?.scheduleSuggestions(force: force) }
            suggestionWork = wait
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: wait)
            return
        }
        if let image = item.preview, ocrCache[item.id] == nil, item.textContent == nil {
            guard !ocrPending.contains(item.id) else { return }
            ocrPending.insert(item.id)
            showSuggestionStatus("正在识别素材文字…")
            DesignOCR.read(image) { [weak self] text in
                self?.ocrPending.remove(item.id)
                self?.ocrCache[item.id] = text
                if self?.capturedItem?.id == item.id { self?.scheduleSuggestions() }
            }
            return
        }
        let project = projectPopup?.titleOfSelectedItem ?? "未分类灵感"
        var context = DesignSuggestionContext(title: item.displayTitle, text: item.textContent ?? ocrCache[item.id] ?? "", kind: item.kind, note: noteField?.stringValue ?? "", project: project, location: locationPopup?.titleOfSelectedItem ?? "", memory: canvas.memory(for: project))
        context.materialID = item.id.uuidString
        context.sourceURL = item.sourceURL
        context.textSource = item.textContent == nil ? ((ocrCache[item.id] ?? "").isEmpty ? "unavailable" : "image_ocr") : item.textSource ?? "captured_text"
        context.textTruncated = item.textTruncated
        context.sharedContext = suggestionService.context.requestSnapshot(focusedMaterialID: item.id.uuidString, project: project).modelContext(project: project)
        if !force && lastSuggestionFingerprint == context.fingerprint { return }
        suggestionWork?.cancel()
        suggestionTask?.cancel()
        let generation = UUID()
        suggestionGeneration = generation
        lastSuggestionFingerprint = context.fingerprint
        showSuggestionStatus("AI 正在结合素材和项目生成建议…")
        suggestionHint?.stringValue = item.evidenceSummary
        suggestionHint?.toolTip = item.evidenceSummary + "\n" + (item.isPageReference && !item.hasNoteBody ? "建议将明确标注正文缺失；打开笔记详情后可点重试或重新生成。" : "结合素材内容、个人想法和项目目标生成建议。")
        suggestionRefresh?.isEnabled = false
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.capturedItem?.id == item.id, self.suggestionGeneration == generation else { return }
            self.suggestionTask = self.suggestionService.suggest(context) { [weak self] result in
                guard let self, self.isExpanded, self.capturedItem?.id == item.id, self.suggestionGeneration == generation else { return }
                self.suggestionRefresh?.isEnabled = true
                switch result {
                case .success(let suggestions): self.showSuggestions(suggestions)
                case .failure(let error): self.showSuggestionStatus("生成失败：\(error.localizedDescription)\n可点击「重新生成」重试。")
                }
            }
        }
        suggestionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func showSuggestions(_ suggestions: [DesignSuggestion], accepted: [String] = []) {
        guard let stack = suggestionStack else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        suggestionData = suggestions
        suggestionButtons = suggestions.map { suggestion in
            let row = FlippedView()
            let button = AntCheckbox(suggestion.label)
            button.state = accepted.contains(suggestion.label) ? .on : .off
            button.target = self; button.action = #selector(suggestionSelectionChanged)
            let reason = label("依据：" + suggestion.reason, size: AntType.caption, color: Palette.secondary)
            reason.maximumNumberOfLines = 1
            reason.lineBreakMode = .byTruncatingTail
            let detail = "\(suggestion.label)\n依据：\(suggestion.reason)\n方法：\(DesignSkillCatalog.load(suggestion.skillID)?.name ?? suggestion.skillID)"
            row.toolTip = detail
            button.toolTip = detail
            reason.toolTip = detail
            [button, reason].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; row.addSubview($0) }
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: stack.widthAnchor), row.heightAnchor.constraint(equalToConstant: 38),
                button.topAnchor.constraint(equalTo: row.topAnchor), button.leadingAnchor.constraint(equalTo: row.leadingAnchor), button.trailingAnchor.constraint(equalTo: row.trailingAnchor), button.heightAnchor.constraint(equalToConstant: 20),
                reason.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 2), reason.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 25), reason.trailingAnchor.constraint(equalTo: row.trailingAnchor)
            ])
            return button
        }
        updateSharedMaterial()
    }

    @objc private func refreshSuggestions() {
        if var item = capturedItem, item.isPageReference, !item.hasNoteBody, !item.isLoadingPreview {
            restoreBrowserContext(&item)
            if item.browserContext != nil {
                item.isLoadingPreview = true; capturedItem = item; cancelSuggestions()
                showSuggestionStatus("正在从来源浏览器补读笔记正文…"); resolveContent(item); return
            }
        }
        scheduleSuggestions(force: true)
    }
    func refreshSharedContext() { scheduleSuggestions(force: true) }
    @objc private func suggestionSelectionChanged() { updateSharedMaterial() }
    private func updateSharedMaterial(saved: Bool? = nil) {
        guard let item = capturedItem else { return }
        let project = projectPopup?.titleOfSelectedItem ?? suggestionService.context.project
        let area = locationPopup?.titleOfSelectedItem ?? suggestionService.context.area
        if !capturePresentation || project == suggestionService.context.project { suggestionService.context.setProject(project, area: area) }
        let previous = suggestionService.context.materials.first { $0.id == item.id.uuidString }
        var metadata = item.metadata(preserving: previous?.metadata ?? .init())
        if item.textContent == nil, !(ocrCache[item.id] ?? "").isEmpty { metadata.textSource = "image_ocr"; metadata.textTruncated = false }
        if !suggestionData.isEmpty {
            metadata.generatedSuggestions = suggestionData
            metadata.acceptedSuggestions = suggestionButtons.filter { $0.state == .on }.map(\.title)
            metadata.suggestionEvidence = zip(suggestionButtons, suggestionData).filter { $0.0.state == .on }.map { $0.1 }
        }
        suggestionService.context.upsert(CompanionMaterial(id: item.id.uuidString, project: project, title: item.displayTitle, text: item.textContent ?? ocrCache[item.id] ?? previous?.text ?? "", note: noteField?.stringValue ?? "", area: area, image: item.preview, saved: saved ?? previous?.saved ?? false, metadata: metadata))
    }
    @objc private func suggestionContextChanged() { scheduleSuggestions() }
    func controlTextDidChange(_ notification: Notification) { scheduleSuggestions() }

    private func position(width: CGFloat, height: CGFloat) {
        guard !isDragging else { return }
        let cursor = NSEvent.mouseLocation
        let anchor = pinnedTopLeft.map { NSPoint(x: $0.x + 1, y: $0.y - 1) } ?? cursor
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let proposedX = pinnedTopLeft?.x ?? (visible.maxX - width - 22)
        let proposedY = pinnedTopLeft.map { $0.y - height } ?? (visible.midY - height / 2)
        let x = min(max(visible.minX + 8, proposedX), max(visible.minX + 8, visible.maxX - width - 8))
        let y = min(max(visible.minY + 8, proposedY), max(visible.minY + 8, visible.maxY - height - 8))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: panel.isVisible)
    }

    private func rememberPosition() {
        // An edge handle is not a positioned tray.
        guard !folderDocked else { return }
        if !isExpanded { folderAtEdge = false; folderCenterY = panel.frame.midY }
        pinnedTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        position(width: panel.frame.width, height: panel.frame.height)
        pinnedTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        UserDefaults.standard.set(["x": panel.frame.minX, "top": panel.frame.maxY], forKey: positionDefaultsKey)
    }

    @objc private func minimizeExpanded() {
        updateSharedMaterial(); clipboardIntent = false; minimizedContents = isBrowsingContents; minimizedMaterialID = capturedItem?.id.uuidString
        cancelCurrentPreview(); capturedItem = nil; isExpanded = false
        armEdge()
        if capturePresentation { onDismissInCapture?() }
    }
    @objc private func closeExpanded() {
        minimizedContents = false; updateSharedMaterial()
        cancelCurrentPreview()
        capturedItem = nil
        isExpanded = false
        armEdge()
        if capturePresentation { onDismissInCapture?() }
    }

    @objc private func continueCollecting() {
        updateSharedMaterial()
        cancelCurrentPreview()
        capturedItem = nil
        externalDragActive = false; showFolder(); dropTarget.showTrayAppearance()
        if capturePresentation { onDismissInCapture?() }
    }

    @objc private func addToCanvas() {
        guard let item = capturedItem else { return }
        let card = CanvasCard(
            item: item,
            note: noteField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            project: projectPopup?.titleOfSelectedItem ?? "未分类灵感",
            location: locationPopup?.titleOfSelectedItem?.replacingOccurrences(of: " · AI 推荐", with: "") ?? "待整理收集区",
            acceptedSuggestions: suggestionButtons.filter { $0.state == .on }.map(\.title),
            suggestionEvidence: zip(suggestionButtons, suggestionData).filter { $0.0.state == .on }.map { $0.1 }
        )
        updateSharedMaterial(saved: true)
        canvas.add(card)
        suggestionService.context.record(role: "user", text: "已保存素材《\(item.displayTitle)》，想法：\(card.note)；采纳建议：" + card.acceptedSuggestions.joined(separator: "；"), purpose: "tray_saved", project: card.project)
        cancelSuggestions()
        capturedItem = nil
        isExpanded = false
        armEdge()
    }
}

private final class UserPromptController: NSObject, NSTextFieldDelegate {
    private let minWidth: CGFloat = 250
    private let maxWidth: CGFloat = 420
    private let promptHeight: CGFloat = 44
    private let panel: KeyPanel
    private let input = NSTextField()
    private let sendButton = AntButton("↑", kind: .primary)
    private let contextButton = AntButton("0", kind: .text)
    private var anchor = NSPoint.zero
    private var currentWidth: CGFloat = 250
    private var followsCursor = false
    private var selectionAnchored = false
    private var idleTimer: Timer?
    private var fadeTimer: Timer?
    private let idleDelay: TimeInterval = 5
    private let fadeDuration: TimeInterval = 3
    var onSubmit: ((String, NSPoint) -> Bool)?
    var keepsEditingAfterSubmit = false
    var onEditingChanged: ((Bool) -> Void)?
    var onShowContext: (() -> Void)?
    func setContextCount(_ count: Int) { contextButton.title = "\(count)"; contextButton.toolTip = "Tab 查看共享上下文（\(count) 份）" }
    var isEditing: Bool { panel.isVisible && input.isEditable }
    var isIdleHidden: Bool { panel.isVisible && panel.alphaValue < 0.01 }
    var isFocused: Bool { panel.isKeyWindow && input.isEditable }
    var draft: String { input.isEditable ? input.stringValue : "" }
    func pauseFollowing() { followsCursor = false }
    func resumeEditing() {
        guard isEditing else { return }
        followsCursor = !selectionAnchored; if !selectionAnchored { position(at: NSEvent.mouseLocation) }; panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(input)
        noteInputActivity()
    }
    private func cancelIdleFade() {
        idleTimer?.invalidate(); idleTimer = nil
        fadeTimer?.invalidate(); fadeTimer = nil
    }
    private func noteInputActivity() {
        cancelIdleFade()
        panel.alphaValue = 1
        panel.ignoresMouseEvents = !input.isEditable
        guard panel.isVisible else { return }
        let timer = Timer(timeInterval: idleDelay, repeats: false) { [weak self] _ in self?.beginIdleFade() }
        idleTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func beginIdleFade() {
        idleTimer = nil
        guard panel.isVisible else { return }
        // An unfinished Chinese/Japanese composition is still active input.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { noteInputActivity(); return }
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { self.noteInputActivity(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / self.fadeDuration)
            self.panel.alphaValue = 1 - t * t * (3 - 2 * t)
            if t >= 1 {
                timer.invalidate(); self.fadeTimer = nil
                // Keep the editor and draft, but don't leave an invisible hit target.
                self.panel.ignoresMouseEvents = true
                if self.selectionAnchored { self.panel.orderOut(nil); self.onEditingChanged?(false) }
            }
        }
        fadeTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func noteKeyDown(_ event: NSEvent) {
        guard event.window === panel, input.isEditable else { return }
        noteInputActivity()
    }
    func notePointerActivity(_ event: NSEvent) {
        guard event.window === panel, input.isEditable else { return }; noteInputActivity()
    }
    func setCapturePresentation(_ active: Bool) {
        keepsEditingAfterSubmit = active
        panel.level = NSWindow.Level(rawValue: active ? NSWindow.Level.screenSaver.rawValue + 2 : NSWindow.Level.statusBar.rawValue + 2)
        input.placeholderString = active ? "提问，Enter 发送选区" : "输入任务，Enter 发送"
    }

    override init() {
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 44),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let root = FlippedView()
        rounded(root, color: Palette.accentSoft, radius: AntMetrics.radiusXL, border: Palette.accentBorder)
        elevate(root, level: 2)
        input.placeholderString = "输入任务，Enter 发送"
        input.font = AntType.font()
        input.textColor = Palette.ink
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.usesSingleLineMode = true
        input.cell?.isScrollable = true
        input.cell?.wraps = false
        input.lineBreakMode = .byTruncatingTail
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)
        input.delegate = self
        input.setAccessibilityIdentifier("companion-prompt")
        sendButton.font = .systemFont(ofSize: 14, weight: .bold)
        sendButton.target = self
        sendButton.action = #selector(submit)
        sendButton.setAccessibilityIdentifier("companion-send")
        contextButton.target = self; contextButton.action = #selector(showContext)
        contextButton.setAccessibilityLabel("查看共享上下文")
        [input, contextButton, sendButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            input.trailingAnchor.constraint(equalTo: contextButton.leadingAnchor, constant: -4),
            input.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            contextButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -4),
            contextButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            contextButton.widthAnchor.constraint(equalToConstant: 28),
            contextButton.heightAnchor.constraint(equalToConstant: 28),
            sendButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        panel.contentView = root
        panel.setContentSize(NSSize(width: minWidth, height: promptHeight))
    }

    // Reuse the original editor and timer. Geometry updates never reset either.
    func showForSelection(at point: NSPoint) {
        selectionAnchored = true; followsCursor = false
        if !input.isEditable { input.stringValue = "" }
        input.isEditable = true; input.isSelectable = true; sendButton.isHidden = false
        resizeForContent(); position(at: point)
        if !isFocused { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(input) }
        onEditingChanged?(true); noteInputActivity()
    }
    func repositionSelection(at point: NSPoint) {
        guard selectionAnchored else { return }; position(at: point)
    }
    func hideSelection() {
        guard selectionAnchored else { return }
        cancelIdleFade(); panel.orderOut(nil); onEditingChanged?(false)
    }
    func show(at cursor: NSPoint, draft: String = "") {
        selectionAnchored = false
        input.stringValue = draft
        input.isEditable = true
        input.isSelectable = true
        sendButton.isHidden = false
        panel.ignoresMouseEvents = false
        followsCursor = true
        resizeForContent()
        position(at: cursor)
        onEditingChanged?(true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(input)
        noteInputActivity()
    }

    func follow(cursor: NSPoint) {
        guard followsCursor, panel.isVisible else { return }
        position(at: cursor)
    }

    private func position(at cursor: NSPoint) {
        anchor = cursor
        guard let visible = NSScreen.screens.first(where: { $0.frame.contains(cursor) })?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        var x = cursor.x + 22
        var y = cursor.y - promptHeight - 20
        if x + currentWidth > visible.maxX { x = visible.maxX - currentWidth - 12 }
        if y < visible.minY { y = cursor.y + 22 }
        x = max(visible.minX + 8, min(x, visible.maxX - currentWidth - 8))
        y = max(visible.minY + 8, min(y, visible.maxY - promptHeight - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func resizeForContent() {
        let font = input.font ?? AntType.font()
        let textWidth = ceil((input.stringValue as NSString).size(withAttributes: [.font: font]).width)
        // 14pt leading + 8pt gap + 32pt action + 8pt trailing.
        currentWidth = min(maxWidth, max(minWidth, textWidth + 94))
        panel.setContentSize(NSSize(width: currentWidth, height: promptHeight))
        if panel.isVisible { position(at: anchor) }
    }

    @objc private func submit() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard onSubmit?(text, anchor) != false else { return }
        if keepsEditingAfterSubmit {
            input.stringValue = ""; resizeForContent(); resumeEditing(); onEditingChanged?(true); return
        }
        followsCursor = true
        input.isEditable = false
        input.isSelectable = false
        sendButton.isHidden = true
        panel.makeFirstResponder(nil)
        panel.ignoresMouseEvents = true
        onEditingChanged?(false)
        noteInputActivity()
    }
    @objc private func showContext() { followsCursor = false; onShowContext?() }

    func reset() {
        cancelIdleFade(); panel.alphaValue = 1
        followsCursor = false; selectionAnchored = false
        input.stringValue = ""
        input.isEditable = true
        input.isSelectable = true
        sendButton.isHidden = false
        panel.ignoresMouseEvents = false
        panel.orderOut(nil)
        onEditingChanged?(false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { submit(); return true }
        if commandSelector == #selector(NSResponder.insertTab(_:)) { showContext(); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { reset(); return true }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        noteInputActivity()
        resizeForContent()
    }
}

private final class AnswerTextView: NSTextView {
    var onInteraction: (() -> Void)?
    var onSelectionEnded: (() -> Void)?
    private(set) var isDraggingSelection = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        isDraggingSelection = true
        defer { isDraggingSelection = false; onSelectionEnded?() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        // Read-only NSTextView can retain its selected range after a plain click.
        // Explicitly dismiss it on a click, so buffered streaming can resume.
        let down = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        let up = NSEvent.mouseLocation
        if event.clickCount == 1, hypot(down.x - up.x, down.y - up.y) < 3 {
            let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            setSelectedRange(NSRange(location: index, length: 0))
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
            if event.charactersIgnoringModifiers == "c" { copy(nil); return true }
            if event.charactersIgnoringModifiers == "a" { selectAll(nil); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class AgentAnswerController {
    private let panel: KeyPanel
    private let status = NSTextField(labelWithString: "")
    private let answer = AnswerTextView()
    private let answerScroll = NSScrollView()
    private let closeButton = AntButton("×", kind: .text)
    private let collapseButton = AntButton("−", kind: .text)
    private let copyButton = AntButton("", kind: .text)
    private let historyButton = AntButton("", kind: .text)
    private let stopButton = AntButton("", kind: .text)
    private weak var companionPanel: NSWindow?
    private var collapsed = false
    private var anchor = NSRect.zero
    private var savedScrollOrigin = NSPoint.zero
    private var copyFeedbackID = UUID()
    private var latestText = ""
    private var renderScheduled = false
    private var rendering = false
    private var renderGeneration = UUID()
    private var selectionObserver: NSObjectProtocol?
    var onStop: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var onInteraction: (() -> Void)?

    init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 36), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "鼠标伙伴回答"
        panel.setAccessibilityIdentifier("companion-answer-window")
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        let root = FlippedView()
        rounded(root, color: Palette.panel, radius: AntMetrics.radiusXL, border: Palette.borderSecondary)
        elevate(root, level: 3)
        let header = FlippedView()
        let badge = label("✦", size: AntType.body, weight: .semibold, color: Palette.accent)
        badge.toolTip = "鼠标伙伴"
        status.font = AntType.font(AntType.caption); status.textColor = Palette.accent
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        answer.isEditable = false; answer.isSelectable = true; answer.drawsBackground = false
        answer.isVerticallyResizable = true; answer.isHorizontallyResizable = false
        answer.minSize = .zero; answer.maxSize = NSSize(width: 1000000, height: 1000000)
        answer.textContainerInset = .zero; answer.textContainer?.lineFragmentPadding = 0
        answer.textContainer?.widthTracksTextView = false
        answer.setAccessibilityIdentifier("companion-answer-text")
        answer.onInteraction = { [weak self] in self?.onInteraction?() }
        answer.onSelectionEnded = { [weak self] in self?.renderLatest() }
        selectionObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: answer, queue: .main) { [weak self] _ in
            guard let self, !self.rendering else { return }
            self.scheduleRender()
        }
        answerScroll.documentView = answer
        answerScroll.drawsBackground = false; answerScroll.hasVerticalScroller = true
        answerScroll.hasHorizontalScroller = false; answerScroll.autohidesScrollers = true
        answerScroll.scrollerStyle = .overlay; answerScroll.borderType = .noBorder
        closeButton.font = .systemFont(ofSize: 18, weight: .medium)
        closeButton.toolTip = "关闭回答"; closeButton.setAccessibilityLabel("关闭回答")
        closeButton.target = self; closeButton.action = #selector(hide)
        closeButton.setAccessibilityIdentifier("answer-close")
        collapseButton.font = .systemFont(ofSize: 17)
        collapseButton.toolTip = "折叠回答"; collapseButton.setAccessibilityLabel("折叠回答")
        collapseButton.target = self; collapseButton.action = #selector(toggleCollapsed)
        collapseButton.setAccessibilityIdentifier("answer-collapse")
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageOnly
        copyButton.toolTip = "复制完整回答"; copyButton.setAccessibilityLabel("复制完整回答")
        copyButton.target = self; copyButton.action = #selector(copyAnswer)
        copyButton.setAccessibilityIdentifier("answer-copy")
        historyButton.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        historyButton.imagePosition = .imageOnly
        historyButton.toolTip = "查看项目历史对话"; historyButton.setAccessibilityLabel("查看项目历史对话")
        historyButton.target = self; historyButton.action = #selector(showHistory)
        historyButton.setAccessibilityIdentifier("answer-history")
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
        stopButton.imagePosition = .imageOnly
        stopButton.toolTip = "停止生成"; stopButton.setAccessibilityLabel("停止生成")
        stopButton.setAccessibilityIdentifier("answer-stop")
        stopButton.target = self; stopButton.action = #selector(stopGeneration)
        stopButton.isHidden = true
        let actions = NSStackView(views: [historyButton, copyButton, stopButton, collapseButton, closeButton])
        actions.orientation = .horizontal; actions.spacing = 2
        for button in [historyButton, copyButton, stopButton, collapseButton, closeButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 24), button.heightAnchor.constraint(equalToConstant: 24)])
        }
        [header, answerScroll].forEach { root.addSubview($0) }
        header.translatesAutoresizingMaskIntoConstraints = false
        [badge, status, actions].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; header.addSubview($0) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor), header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor), header.heightAnchor.constraint(equalToConstant: AnswerBubbleLayout.headerHeight),
            badge.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12), badge.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 14),
            status.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8), status.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),
            actions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6), actions.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        panel.contentView = root
        answerScroll.isHidden = true; copyButton.isEnabled = false
    }

    func attach(to companionPanel: NSWindow) { self.companionPanel = companionPanel }
    func setCapturePresentation(_ active: Bool) {
        panel.level = NSWindow.Level(rawValue: active ? NSWindow.Level.screenSaver.rawValue + 3 : NSWindow.Level.statusBar.rawValue + 1)
    }
    private func attachForDisplay() {
        guard panel.parent == nil, let companionPanel else { return }
        companionPanel.addChildWindow(panel, ordered: .above)
    }
    func showWorking(belowLeftOf agentFrame: NSRect) {
        attachForDisplay(); anchor = agentFrame
        latestText = ""; renderGeneration = UUID(); renderScheduled = false
        stopButton.isHidden = false; stopButton.isEnabled = true
        status.stringValue = "正在理解…"; status.textColor = Palette.accent
        rendering = true
        answer.textStorage?.setAttributedString(NSAttributedString(string: ""))
        answer.setSelectedRange(NSRange(location: 0, length: 0)); rendering = false
        copyButton.isEnabled = false; savedScrollOrigin = .zero
        resizeForContent(); panel.orderFrontRegardless()
    }
    func updateStatus(_ text: String) {
        status.stringValue = text; status.textColor = Palette.accent
        if panel.isVisible { resizeForContent() }
    }
    func showAnswer(_ text: String, belowLeftOf agentFrame: NSRect) {
        attachForDisplay(); anchor = agentFrame
        stopButton.isHidden = true
        status.stringValue = "已完成"; status.textColor = Palette.green
        latestText = text; copyButton.isEnabled = !text.isEmpty
        renderLatest()
    }
    func showPartial(_ text: String) {
        latestText = text; status.stringValue = "正在生成…"; status.textColor = Palette.accent
        copyButton.isEnabled = !text.isEmpty
        scheduleRender()
    }
    func showFailure(_ message: String) {
        stopButton.isHidden = true
        latestText += latestText.isEmpty ? message : "\n\n---\n\n生成中断：" + message
        status.stringValue = "未完成"; status.textColor = .systemOrange
        copyButton.isEnabled = !latestText.isEmpty; renderLatest()
    }
    func showStopped() {
        stopButton.isHidden = true; stopButton.isEnabled = false
        status.stringValue = "已停止，已生成内容仍保留"; status.textColor = Palette.accent
        renderLatest()
    }
    @objc private func stopGeneration() {
        guard !stopButton.isHidden, stopButton.isEnabled else { return }
        stopButton.isEnabled = false
        onInteraction?(); onStop?(); showStopped()
    }
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        let token = renderGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, token == self.renderGeneration else { return }
            self.renderScheduled = false; self.renderLatest()
        }
    }
    private func renderLatest() {
        // Keep the text and bubble stationary while someone is selecting/copying.
        // Network delivery continues; deselecting reveals the newest buffered text.
        guard !rendering, !answer.isDraggingSelection, answer.selectedRange().length == 0 else { return }
        rendering = true; defer { rendering = false }
        let oldOrigin = answerScroll.contentView.bounds.origin
        let followsEnd = answer.frame.height - oldOrigin.y - answerScroll.contentSize.height < 24
        let value = markdownAttributedString(latestText)
        if !answer.attributedString().isEqual(to: value) { answer.textStorage?.setAttributedString(value) }
        resizeForContent()
        let maxY = max(0, answer.frame.height - answerScroll.contentSize.height)
        answerScroll.contentView.scroll(to: NSPoint(x: 0, y: followsEnd ? maxY : min(oldOrigin.y, maxY)))
        answerScroll.reflectScrolledClipView(answerScroll.contentView)
    }
    private func resizeForContent() {
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let text = answer.attributedString()
        let layout = AnswerBubbleLayout.measure(text, status: status.stringValue, collapsed: collapsed, available: visible.size, actionCount: stopButton.isHidden ? 4 : 5)
        answerScroll.isHidden = collapsed || text.length == 0
        panel.setContentSize(layout.size)
        if !answerScroll.isHidden {
            answerScroll.frame = NSRect(x: 12, y: 38, width: layout.size.width - 24, height: max(0, layout.size.height - 48))
            answerScroll.tile()
            answer.textContainer?.containerSize = NSSize(width: layout.textWidth, height: 1000000)
            answer.setFrameSize(NSSize(width: answerScroll.contentSize.width, height: max(layout.textHeight, answerScroll.contentSize.height)))
            answer.layoutManager?.ensureLayout(for: answer.textContainer!)
        }
        panel.contentView?.layoutSubtreeIfNeeded(); position(belowLeftOf: anchor)
    }
    @objc private func toggleCollapsed() {
        onInteraction?()
        if !collapsed { savedScrollOrigin = answerScroll.contentView.bounds.origin }
        collapsed.toggle()
        collapseButton.title = collapsed ? "+" : "−"
        collapseButton.toolTip = collapsed ? "展开回答" : "折叠回答"
        collapseButton.setAccessibilityLabel(collapsed ? "展开回答" : "折叠回答")
        resizeForContent()
        if !collapsed { answerScroll.contentView.scroll(to: savedScrollOrigin); answerScroll.reflectScrolledClipView(answerScroll.contentView) }
    }
    @objc private func copyAnswer() {
        guard !latestText.isEmpty else { return }
        onInteraction?()
        let pasteboard = NSPasteboard.general
        let value = markdownAttributedString(latestText)
        pasteboard.clearContents(); pasteboard.setString(value.string, forType: .string)
        if let rtf = try? value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) { pasteboard.setData(rtf, forType: .rtf) }
        let id = UUID(); copyFeedbackID = id
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        copyButton.toolTip = "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.copyFeedbackID == id else { return }
            self.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil); self.copyButton.toolTip = "复制完整回答"
        }
    }
    @objc private func showHistory() { onInteraction?(); onShowHistory?() }
    func reposition(belowLeftOf frame: NSRect) { anchor = frame; if panel.isVisible { position(belowLeftOf: frame) } }
    @objc func hide() {
        panel.orderOut(nil); companionPanel?.removeChildWindow(panel)
        collapsed = false; collapseButton.title = "−"; collapseButton.toolTip = "折叠回答"; collapseButton.setAccessibilityLabel("折叠回答")
    }
    private func position(belowLeftOf frame: NSRect) {
        anchor = frame
        guard let visible = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let x = min(max(visible.minX + 8, frame.minX - panel.frame.width + 34), max(visible.minX + 8, visible.maxX - panel.frame.width - 8))
        let below = frame.minY - panel.frame.height - 10
        let proposedY = below >= visible.minY + 8 ? below : frame.maxY + 10
        let y = min(max(visible.minY + 8, proposedY), max(visible.minY + 8, visible.maxY - panel.frame.height - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class InspirationController: NSObject {
    private let agentService = AgentAPIService(context: CompanionContext(store: MacWorkspaceStorage.projectStore()))
    private lazy var canvasSmartTags = CanvasSmartTagCoordinator(service: agentService, context: agentService.context) { [weak self] payload in
        self?.canvas.workspace.receiveSmartTagResult(payload)
    }
    private lazy var canvas = CanvasController(context: agentService.context)
    private lazy var tray = TrayController(canvas: canvas, agent: agentService)
    private lazy var capture = ContextCaptureController(context: agentService.context)
    private lazy var contextReview = ContextReviewController(context: agentService.context)
    private lazy var history = CompanionHistoryController(context: agentService.context)
    private let userPrompt = UserPromptController()
    private let agentAnswer = AgentAnswerController()
    private let companionPanel: NSPanel
    private var monitors: [Any] = []
    private var browserDragOrigin: BrowserDragContext?
    private var isDraggingCompanion = false
    private var contextObservation: UUID?
    private var sourceObservation: NSObjectProtocol?
    private var lastExternalSource: ContextSource?
    private var agentRequest: CompanionAgentRequest?
    private var conversationGeneration = UUID()
    private var promptDraft = ""
    private var canvasDraftCards: [[String: Any]]?
    private var canvasDraftRequestID = ""
    private var canvasSelectionSession = ""
    private var agentBusy = false
    private var displayedProject = ""
    private(set) var isActive = false
    var onPromptEditingChanged: ((Bool) -> Void)?
    var onModeChanged: (() -> Void)?

    override init() {
        companionPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 52, height: 52),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        companionPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        companionPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        companionPanel.isOpaque = false
        companionPanel.backgroundColor = .clear
        companionPanel.hasShadow = false
        companionPanel.hidesOnDeactivate = false
        companionPanel.ignoresMouseEvents = false
        buildAgentPointer()
        agentAnswer.attach(to: companionPanel)
        agentAnswer.onShowHistory = { [weak self] in self?.showHistory() }
        agentAnswer.onInteraction = { [weak self] in self?.userPrompt.pauseFollowing() }
        userPrompt.onSubmit = { [weak self] prompt, _ in
            guard let self else { return false }
            if let cards = self.canvasDraftCards {
                self.canvasDraftCards = nil
                self.runCanvasAgent(prompt: prompt, cards: cards, requestID: self.canvasDraftRequestID)
                return true
            }
            if self.capture.isActive, !self.capture.commit() { return false }
            self.runAgent(prompt: prompt); return true
        }
        userPrompt.onEditingChanged = { [weak self] editing in
            guard let self else { return }; self.onPromptEditingChanged?(editing || self.capture.isActive)
        }
        userPrompt.onShowContext = { [weak self] in self?.showContext() }
        contextReview.onAnnotate = { [weak self] in self?.showPrompt() }
        contextReview.onDismiss = { [weak self] in self?.userPrompt.resumeEditing() }
        contextReview.onProjectSelected = { [weak self] in self?.selectProject($0) }
        contextReview.onOpenMaterial = { [weak self] in self?.tray.openMaterial($0) }
        contextReview.onShowHistory = { [weak self] in self?.showHistory() }
        capture.onReady = { [weak self] in
            guard let self else { return }
            self.setCapturePresentation(true)
            self.userPrompt.show(at: NSEvent.mouseLocation, draft: self.promptDraft)
        }
        capture.onFocusPrompt = { [weak self] in self?.userPrompt.resumeEditing() }
        capture.onReviewContext = { [weak self] in self?.showContext() }
        capture.onContextConfirmed = { [weak self] in self?.tray.refreshSharedContext() }
        capture.onCollectToTray = { [weak self] ids in
            self?.userPrompt.pauseFollowing(); self?.tray.showCollection(ids)
        }
        tray.onDismissInCapture = { [weak self] in self?.userPrompt.resumeEditing() }
        capture.onFinish = { [weak self] _ in
            guard let self else { return }
            self.setCapturePresentation(false)
            self.onPromptEditingChanged?(self.userPrompt.isEditing)
            self.userPrompt.resumeEditing()
        }
        contextObservation = agentService.context.observe { [weak self] in
            guard let self else { return }; self.userPrompt.setContextCount(self.agentService.context.count)
            if self.displayedProject != self.agentService.context.project {
                self.displayedProject = self.agentService.context.project; self.canvas.reload()
            }
        }
        userPrompt.setContextCount(agentService.context.count)
        displayedProject = agentService.context.project
        canvas.workspace.onProjectSelected = { [weak self] in self?.selectProject($0) }
        canvas.workspace.onWorkMode = { [weak self] active in
            guard let self else { return }
            UserDefaults.standard.set(active, forKey: "weavia.inspirationModeEnabled")
            active ? self.activate() : self.deactivate()
        }
        canvas.workspace.onSettings = { [weak self] in self?.configureAPIKey() }
        canvas.workspace.onHistory = { [weak self] in self?.showHistory() }
        canvas.workspace.onOpenMaterial = { [weak self] in self?.tray.openMaterial($0) }
        canvas.workspace.onCancelAgent = { [weak self] in self?.stopAgentGeneration() }
        agentAnswer.onStop = { [weak self] in self?.stopAgentGeneration() }
        canvas.workspace.onSelection = { [weak self] rect, cards, session, completed, explicit in
            self?.presentCanvasSelection(rect: rect, cards: cards, session: session, completed: completed, explicit: explicit)
        }
        canvas.workspace.onSelectionEnded = { [weak self] in
            self?.canvasSelectionSession = ""; self?.userPrompt.hideSelection()
        }
        canvas.workspace.onSmartTags = { [weak self] card, requestID in
            guard let self else { return }; self.canvasSmartTags.generate(card: card, requestID: requestID, window: self.canvas.workspace.window)
        }
        canvas.workspace.onCancelSmartTags = { [weak self] requestID in self?.canvasSmartTags.cancel(requestID: requestID) }
        canvas.workspace.onAgent = { [weak self] prompt, cards, requestID in self?.runCanvasAgent(prompt: prompt, cards: cards, requestID: requestID) }
        agentService.onInputMode = { [weak self] text in self?.agentAnswer.updateStatus(text) }
        sourceObservation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.lastExternalSource = ContextSource(name: app.localizedName ?? "当前应用", bundleID: app.bundleIdentifier, pid: app.processIdentifier)
        }
    }

    private func buildAgentPointer() {
        let root = CompanionDragView()
        root.onClick = { [weak self] in self?.showPrompt() }
        root.onMoved = { [weak self] in
            guard let self else { return }
            self.agentAnswer.reposition(belowLeftOf: self.companionPanel.frame)
        }
        root.onDragStateChanged = { [weak self] dragging in self?.isDraggingCompanion = dragging }
        let cursor = AgentCursorView(frame: .zero)
        cursor.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(cursor)
        NSLayoutConstraint.activate([
            cursor.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            cursor.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            cursor.widthAnchor.constraint(equalToConstant: 44),
            cursor.heightAnchor.constraint(equalToConstant: 44)
        ])
        companionPanel.contentView = root
    }

    func toggle() { isActive ? deactivate() : activate() }

    func activate() {
        guard !isActive else { return }
        isActive = true
        canvas.workspace.setMode(true)
        showCompanion()
        tray.armEdge()
        installMonitors()
        onModeChanged?()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        canvas.workspace.setMode(false)
        capture.cancel()
        agentRequest?.cancel(); conversationGeneration = UUID()
        userPrompt.reset()
        companionPanel.orderOut(nil)
        tray.hideAll()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        canvasDraftCards = nil
        canvasDraftRequestID = ""; canvasSelectionSession = ""; agentBusy = false
        onModeChanged?()
    }

    func showCanvas() { canvas.setCapturePresentation(capture.isActive); canvas.show() }
    func showProjectHome() { canvas.setCapturePresentation(capture.isActive); canvas.showProjectHome() }
    func showTray() { tray.showContents() }
    func showPrompt() {
        canvasDraftCards = nil
        if capture.isActive { userPrompt.resumeEditing(); return }
        let front = ContextSource.current()
        let source = front.pid == ProcessInfo.processInfo.processIdentifier ? lastExternalSource ?? front : front
        if !isActive { activate() }
        promptDraft = userPrompt.draft
        userPrompt.reset(); contextReview.window?.orderOut(nil)
        onPromptEditingChanged?(true)
        capture.begin(source: source)
    }
    private func setCapturePresentation(_ active: Bool) {
        companionPanel.level = NSWindow.Level(rawValue: active ? NSWindow.Level.screenSaver.rawValue + 6 : NSWindow.Level.statusBar.rawValue + 3)
        userPrompt.setCapturePresentation(active); agentAnswer.setCapturePresentation(active)
        tray.setCapturePresentation(active)
        if active, let frame = capture.displayFrame, !frame.intersects(companionPanel.frame) {
            companionPanel.setFrameOrigin(NSPoint(x: frame.maxX - 150, y: frame.midY + 110))
        }
        companionPanel.orderFrontRegardless()
        if !active {
            canvas.setCapturePresentation(false); MaterialPreviewController.restoreNormalLevels()
            contextReview.window?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
            history.window?.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 4)
        }
    }
    func showContext() {
        userPrompt.pauseFollowing()
        contextReview.window?.level = NSWindow.Level(rawValue: capture.isActive ? NSWindow.Level.screenSaver.rawValue + 5 : NSWindow.Level.statusBar.rawValue + 4)
        contextReview.show()
    }
    func showHistory() {
        userPrompt.pauseFollowing()
        history.window?.level = NSWindow.Level(rawValue: capture.isActive ? NSWindow.Level.screenSaver.rawValue + 7 : NSWindow.Level.statusBar.rawValue + 4)
        history.show()
    }
    private func selectProject(_ name: String) {
        guard name != agentService.context.project else { return }
        canvasSelectionSession = ""; canvasDraftCards = nil; canvasDraftRequestID = ""; agentBusy = false
        capture.cancel(); agentRequest?.cancel(); conversationGeneration = UUID()
        userPrompt.reset(); agentAnswer.hide(); tray.hideAll()
        agentService.context.selectProject(name)
    }
    func flushProject() -> String? { tray.hideAll(); return agentService.context.flush() }
    func configureAPIKey() { agentService.promptForAPIKey() }

    private func showCompanion() {
        let screen = capture.displayFrame.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        companionPanel.setFrameOrigin(NSPoint(x: visible.maxX - 150, y: visible.midY + 110))
        companionPanel.orderFrontRegardless()
    }

    private func moveAgent(to point: NSPoint, duration: TimeInterval = 0.30) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            companionPanel.animator().setFrameOrigin(point)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.agentAnswer.reposition(belowLeftOf: self.companionPanel.frame)
        }
    }

    private func presentCanvasSelection(rect: NSRect, cards: [[String: Any]], session: String, completed: Bool, explicit: Bool) -> NSPoint? {
        guard isActive, !capture.isActive, !agentBusy, !isDraggingCompanion, !tray.isDragging,
              NSApp.isActive, (canvas.workspace.window.isKeyWindow || userPrompt.isFocused), !cards.isEmpty else { return nil }
        if !completed && canvasSelectionSession != session { return nil }
        // A pending draft retains its original references until sent or explicitly discarded.
        let sameCards = (canvasDraftCards ?? []).compactMap { $0["id"] as? String }.sorted() == cards.compactMap { $0["id"] as? String }.sorted()
        if completed && !userPrompt.draft.isEmpty && (!sameCards || canvasDraftCards == nil) { return nil }
        guard let visible = NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.visibleFrame ?? NSScreen.main?.visibleFrame else { return nil }
        let viewport = canvas.workspace.window.convertToScreen(canvas.workspace.webView.convert(canvas.workspace.webView.bounds, to: nil)).intersection(visible)
        let x = min(visible.maxX - 60, max(visible.minX + 8, rect.maxX + 8))
        // Leave room for the options above and the native prompt below whenever possible.
        let y = max(viewport.minY + 80, min(rect.midY - 26, viewport.maxY - 250))
        let point = NSPoint(x: x, y: y)
        canvasSelectionSession = session
        companionPanel.setFrameOrigin(point); companionPanel.orderFrontRegardless()
        let anchor = NSPoint(x: point.x + 20, y: point.y + 20)
        agentAnswer.reposition(belowLeftOf: companionPanel.frame)
        if completed {
            agentAnswer.hide()
            canvasDraftCards = cards; canvasDraftRequestID = session
            userPrompt.setContextCount(cards.count)
            userPrompt.showForSelection(at: anchor)
        } else { userPrompt.repositionSelection(at: anchor) }
        return anchor
    }

    private func stopAgentGeneration() {
        agentRequest?.cancel(); agentRequest = nil
        conversationGeneration = UUID()
        agentBusy = false
        agentAnswer.showStopped()
    }

    private func runCanvasAgent(prompt: String, cards: [[String: Any]], requestID: String) {
        if !isActive { activate() }
        if prompt.isEmpty {
            canvasDraftCards = cards; canvasDraftRequestID = requestID
            userPrompt.show(at: NSEvent.mouseLocation, draft: "")
            userPrompt.setContextCount(cards.count)
            return
        }
        if userPrompt.draft.isEmpty { canvasDraftCards = nil }
        canvasSelectionSession = ""; userPrompt.hideSelection(); agentBusy = true
        agentRequest?.cancel()
        let project = agentService.context.project
        let snapshot = agentService.context.requestSnapshot()
        _ = snapshot.beginCaptureSession()
        for card in cards.prefix(8) {
            let materialID = card["nativeMaterialId"] as? String ?? ""
            let original = agentService.context.materials.first { $0.id == materialID && $0.project == project }
            var image = original?.image
            if image == nil, let dataURL = card["imageDataURL"] as? String, dataURL.count < 16 * 1024 * 1024,
               dataURL.hasPrefix("data:image/"), let comma = dataURL.firstIndex(of: ","),
               let bytes = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) { image = NSImage(data: bytes) }
            let title = String((card["title"] as? String ?? original?.title ?? "画布所选内容").prefix(500))
            let text = String((card["text"] as? String ?? original?.text ?? "").prefix(16000))
            let asset = CompanionContextAsset(title: title, text: text, image: image, sourceApp: "CUPPA 项目画布", sourceURL: card["url"] as? String ?? original?.metadata.sourceURL, kind: "用户选择的画布卡片")
            _ = snapshot.add(asset)
            agentService.context.retainCanvasHistory(asset)
        }
        let generation = UUID(); conversationGeneration = generation
        agentAnswer.showWorking(belowLeftOf: companionPanel.frame)
        agentRequest = agentService.send(prompt, snapshot: snapshot, onPartial: { [weak self] text in
            guard let self, self.conversationGeneration == generation else { return }
            self.agentAnswer.showPartial(text)
            self.canvas.workspace.receiveAgentResult(requestID: requestID, status: "streaming", text: text, project: project)
        }) { [weak self] result in
            guard let self, self.conversationGeneration == generation else { return }
            self.agentBusy = false
            switch result {
            case .success(let text):
                self.agentAnswer.showAnswer(text, belowLeftOf: self.companionPanel.frame)
                self.canvas.workspace.receiveAgentResult(requestID: requestID, status: "completed", text: text, project: project)
            case .failure(let error):
                self.agentAnswer.showFailure(error.localizedDescription)
                self.canvas.workspace.receiveAgentResult(requestID: requestID, status: "failed", text: error.localizedDescription, project: project)
            }
        }
    }

    private func runAgent(prompt: String) {
        agentBusy = true
        agentRequest?.cancel()
        let requestContext = agentService.context.requestSnapshot()
        agentService.context.record(role: "user", text: prompt, purpose: "conversation", project: requestContext.project, referenceIDs: requestContext.currentAssets.map(\.id))
        let generation = UUID(); conversationGeneration = generation
        let screen = capture.displayFrame.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { agentBusy = false; return }
        let workPoint = NSPoint(x: visible.maxX - 180, y: visible.maxY - 170)
        moveAgent(to: workPoint)
        var targetFrame = companionPanel.frame
        targetFrame.origin = workPoint
        agentAnswer.showWorking(belowLeftOf: targetFrame)
        func sendWhenReady(attempts: Int = 0) {
            guard conversationGeneration == generation else { return }
            requestContext.refreshPendingOCR(from: agentService.context)
            if requestContext.isPreparing {
                agentAnswer.updateStatus("正在识别圈画中的文字…")
                guard attempts < 100 else { agentBusy = false; agentAnswer.showAnswer("圈画文字仍在识别，请稍后重新发送。", belowLeftOf: targetFrame); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { sendWhenReady(attempts: attempts + 1) }; return
            }
            agentRequest = agentService.send(prompt, snapshot: requestContext, recordUser: false, onPartial: { [weak self] text in
                guard let self, self.conversationGeneration == generation else { return }
                self.agentAnswer.showPartial(text)
            }) { [weak self] result in
            guard let self, self.conversationGeneration == generation else { return }
            self.agentBusy = false
            switch result {
            case .success(let text):
                self.agentAnswer.showAnswer(text, belowLeftOf: self.companionPanel.frame)
            case .failure(let error):
                let nsError = error as NSError
                var message = error.localizedDescription
                if nsError.code == 401 && message.contains("尚未设置") {
                    message += "\n请从菜单栏的“设置 Agent API…”保存 Key。"
                } else if nsError.code == 403 && message.contains("网络环境") {
                    message += "\n请连接同济校园网或学校 VPN 后重试。"
                }
                self.agentAnswer.showFailure(message)
            }
        }
        }
        sendWhenReady()
    }

    private func dragStarted() {
        guard isActive, !capture.isActive, !isDraggingCompanion, !tray.isDragging else { return }
        tray.setDragContext(browserDragOrigin)
        if tray.isExpanded { return }
        tray.showDropTarget(sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName ?? "当前应用", dragging: true)
    }

    private func dragEnded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in self?.tray.hideIfCompact() }
    }

    private func clipboardCopyDetected(sourceApp: String) {
        guard isActive else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let context: BrowserDragContext? = app.flatMap { app in
            guard let bundle = app.bundleIdentifier, BrowserCaptureRequest.supportedBrowsers.contains(bundle) else { return nil }
            let point = NSEvent.mouseLocation
            return BrowserDragContext(bundleID: bundle, processID: app.processIdentifier, screenPoint: CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.isActive else { return }
            let pasteboard = NSPasteboard.general
            let textTypes: [NSPasteboard.PasteboardType] = [
                .string, .html, .rtf, .rtfd,
                NSPasteboard.PasteboardType("public.utf8-plain-text"),
                NSPasteboard.PasteboardType("public.utf16-external-plain-text"),
                NSPasteboard.PasteboardType("public.text"),
                NSPasteboard.PasteboardType("public.plain-text"),
                NSPasteboard.PasteboardType("text/plain")
            ]
            guard textTypes.contains(where: { pasteboard.availableType(from: [$0]) != nil }) else { return }
            self.tray.prepareForClipboardPaste(sourceApp: sourceApp, browserContext: context)
        }
    }

    private func installMonitors() {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            self?.browserDragOrigin = nil
            self?.userPrompt.notePointerActivity(event)
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            guard let self, let app = NSWorkspace.shared.frontmostApplication,
                  let bundle = app.bundleIdentifier, BrowserCaptureRequest.supportedBrowsers.contains(bundle) else {
                self?.browserDragOrigin = nil
                return
            }
            let point = NSEvent.mouseLocation
            let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
            self.browserDragOrigin = BrowserDragContext(bundleID: bundle, processID: app.processIdentifier, screenPoint: CGPoint(x: point.x, y: screenTop - point.y))
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                if self?.capture.isActive == true { self?.capture.cancel(); return }
                MaterialPreviewController.dismissVisible()
                self?.userPrompt.reset()
                self?.agentAnswer.hide()
            } else if event.keyCode == UInt16(kVK_ANSI_C), event.modifierFlags.contains(.command) {
                let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "当前应用"
                self?.clipboardCopyDetected(sourceApp: source)
            }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if self?.capture.isActive == true, self?.userPrompt.isIdleHidden == true,
               event.keyCode == UInt16(kVK_ANSI_Slash), event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                self?.userPrompt.resumeEditing(); return nil
            }
            self?.userPrompt.noteKeyDown(event)
            if event.keyCode == UInt16(kVK_ANSI_V), event.modifierFlags.contains(.command), self?.tray.pasteFromClipboardIfFocused() == true { return nil }
            if self?.capture.isActive == true {
                let editingText = (event.window?.firstResponder as? NSTextView)?.isEditable == true
                if event.keyCode == UInt16(kVK_Escape) { self?.capture.cancel(); return nil }
                if event.keyCode == UInt16(kVK_ANSI_Slash), event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, !editingText { self?.userPrompt.resumeEditing(); return nil }
                if event.keyCode == UInt16(kVK_ANSI_V), event.modifierFlags.contains(.command), !editingText { self?.capture.pasteText(); return nil }
                return event
            }
            if event.keyCode == UInt16(kVK_ANSI_V), event.modifierFlags.contains(.command), self?.tray.pasteFromClipboardIfFocused() == true {
                return nil
            }
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            MaterialPreviewController.dismissVisible()
            self?.userPrompt.reset()
            self?.agentAnswer.hide()
            return nil
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in self?.userPrompt.follow(cursor: event.locationInWindow) }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in self?.userPrompt.follow(cursor: NSEvent.mouseLocation); return event }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in self?.dragStarted() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] event in self?.userPrompt.notePointerActivity(event); self?.userPrompt.follow(cursor: NSEvent.mouseLocation); return event }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in self?.dragEnded() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in self?.dragEnded(); return event }) { monitors.append(monitor) }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var inspiration: InspirationController!
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var trayHotKeyRef: EventHotKeyRef?
    private var promptHotKeyRef: EventHotKeyRef?
    private var slashHotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do { try MacWorkspaceStorage.prepareLegacyImport() }
        catch {
            let alert = NSAlert(); alert.messageText = "旧项目尚未复制完成"
            alert.informativeText = "原项目未改动。请检查磁盘空间与文件权限，再重新打开应用。\n" + error.localizedDescription
            alert.runModal(); NSApp.stop(nil); return
        }
        MacWorkspaceStorage.inheritInterfacePreferences()
        inspiration = InspirationController()
        inspiration.onPromptEditingChanged = { [weak self] editing in
            guard let self else { return }
            editing ? self.unregisterSlashHotKey() : self.registerSlashHotKeyIfNeeded()
        }
        inspiration.onModeChanged = { [weak self] in
            guard let self else { return }
            self.inspiration.isActive ? self.registerSlashHotKeyIfNeeded() : self.unregisterSlashHotKey()
            self.rebuildMenu()
        }
        configureApplicationMenu()
        configureMenuBar()
        registerHotKey()
        // Keep the original Mac companion available on launch. Only an explicit
        // user choice of Focus mode disables its floating UI and slash shortcut.
        if UserDefaults.standard.object(forKey: "weavia.inspirationModeEnabled") as? Bool ?? true {
            inspiration.activate()
            registerSlashHotKeyIfNeeded()
        }
        rebuildMenu()
        inspiration.showProjectHome()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        inspiration?.showProjectHome()
        return true
    }

    private func configureApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "WEAVIA")
        appMenu.addItem(withTitle: "隐藏 WEAVIA", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 WEAVIA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        let canvas = NSMenuItem(title: "打开项目画布", action: #selector(openCanvas), keyEquivalent: "0"); canvas.target = self; fileMenu.addItem(canvas)
        let tray = NSMenuItem(title: "显示灵感托盘", action: #selector(showTray), keyEquivalent: ""); tray.target = self; fileMenu.addItem(tray)
        fileItem.submenu = fileMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("重做", "redo:", "Z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.mainMenu = main; NSApp.windowsMenu = windowMenu
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "↖"
        statusItem.button?.toolTip = "WEAVIA · 灵感模式"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: inspiration.isActive ? "退出灵感模式" : "进入灵感模式", action: #selector(toggleInspirationMode), keyEquivalent: "i")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.target = self
        menu.addItem(toggle)
        let prompt = NSMenuItem(title: "和鼠标伙伴对话（/）", action: #selector(showPrompt), keyEquivalent: "p")
        prompt.keyEquivalentModifierMask = [.command, .shift]
        prompt.target = self
        menu.addItem(prompt)
        let context = NSMenuItem(title: "查看共享上下文…", action: #selector(showContext), keyEquivalent: "")
        context.target = self; menu.addItem(context)
        let project = NSMenuItem(title: "切换项目…", action: #selector(showContext), keyEquivalent: "")
        project.target = self; menu.addItem(project)
        let history = NSMenuItem(title: "查看项目对话记录…", action: #selector(showHistory), keyEquivalent: "")
        history.target = self; menu.addItem(history)
        let tray = NSMenuItem(title: "显示灵感托盘", action: #selector(showTray), keyEquivalent: " ")
        tray.keyEquivalentModifierMask = [.control, .shift]
        tray.target = self
        menu.addItem(tray)
        let canvas = NSMenuItem(title: "打开项目画布", action: #selector(openCanvas), keyEquivalent: "o")
        canvas.target = self
        menu.addItem(canvas)
        menu.addItem(.separator())
        let key = NSMenuItem(title: "设置 Agent API…", action: #selector(configureAPIKey), keyEquivalent: "")
        key.target = self
        menu.addItem(key)
        let permissions = NSMenuItem(title: "屏幕录制权限帮助…", action: #selector(showCapturePermissionHelp), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        let help = NSMenuItem(title: "灵感模式中开始拖拽，托盘才会出现", action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 WEAVIA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.contentTintColor = inspiration.isActive ? Palette.accent : Palette.secondary
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.toggleInspirationMode() }
            } else if hotKeyID.id == 2 {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.showTray() }
            } else if hotKeyID.id == 3 {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.showPrompt() }
            } else if hotKeyID.id == 4 {
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.showPrompt() }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        let id = EventHotKeyID(signature: OSType(0x4D434D50), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_I), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        let trayID = EventHotKeyID(signature: OSType(0x4D434D50), id: 2)
        let trayHotKeyStatus = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | shiftKey), trayID, GetApplicationEventTarget(), 0, &trayHotKeyRef)
        if trayHotKeyStatus != noErr { NSLog("Mouse Companion tray hotkey registration failed: %d", trayHotKeyStatus) }
        let promptID = EventHotKeyID(signature: OSType(0x4D434D50), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | shiftKey), promptID, GetApplicationEventTarget(), 0, &promptHotKeyRef)
    }

    private func registerSlashHotKeyIfNeeded() {
        guard inspiration.isActive, slashHotKeyRef == nil else { return }
        let slashID = EventHotKeyID(signature: OSType(0x4D434D50), id: 4)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Slash), 0, slashID, GetApplicationEventTarget(), 0, &slashHotKeyRef)
        if status != noErr { NSLog("Mouse Companion slash hotkey registration failed: %d", status) }
    }

    private func unregisterSlashHotKey() {
        guard let slashHotKeyRef else { return }
        UnregisterEventHotKey(slashHotKeyRef)
        self.slashHotKeyRef = nil
    }

    @objc private func toggleInspirationMode() {
        UserDefaults.standard.set(!inspiration.isActive, forKey: "weavia.inspirationModeEnabled")
        inspiration.toggle()
        inspiration.isActive ? registerSlashHotKeyIfNeeded() : unregisterSlashHotKey()
        rebuildMenu()
    }

    @objc private func openCanvas() { inspiration.showCanvas() }
    @objc private func showTray() { inspiration.showTray() }
    @objc private func showPrompt() { inspiration.showPrompt() }
    @objc private func showContext() { inspiration.showContext() }
    @objc private func showHistory() { inspiration.showHistory() }
    @objc private func configureAPIKey() { inspiration.configureAPIKey() }

    @objc private func showCapturePermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "允许 WEAVIA 进行屏幕录制"
        alert.informativeText = "在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中，允许当前 WEAVIA 应用，然后退出并重新打开 WEAVIA。旧版 Mouse Companion 的权限不会自动授予这个独立应用。\n\n当前应用：\n" + Bundle.main.bundleURL.path + "\n\n如果已经允许，重新打开后仍无法圈选，可能是系统截图服务暂时失败。这里不会自动修改任何系统权限。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let inspiration else { return .terminateNow }
        guard let error = inspiration.flushProject() else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "项目尚未保存完成"; alert.informativeText = error
        alert.addButton(withTitle: "重试保存"); alert.addButton(withTitle: "取消退出"); alert.addButton(withTitle: "仍然退出")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return inspiration.flushProject() == nil ? .terminateNow : .terminateCancel
        case .alertThirdButtonReturn: return .terminateNow
        default: return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        inspiration?.deactivate()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let trayHotKeyRef { UnregisterEventHotKey(trayHotKeyRef) }
        if let promptHotKeyRef { UnregisterEventHotKey(promptHotKeyRef) }
        unregisterSlashHotKey()
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()

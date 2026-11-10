// Full-screen synthetic canvas keeps drag/drop screenshots free of user content.
import AppKit

final class SourceView: NSView, NSDraggingSource {
    let card: Bool
    let preview: NSImage
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(card: Bool) {
        self.card = card
        preview = NSImage(size: NSSize(width: 160, height: 100), flipped: true) { _ in
            NSColor(srgbRed: 0.90, green: 0.94, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 160, height: 100), xRadius: 12, yRadius: 12).fill()
            NSColor.systemBlue.setFill(); NSBezierPath(ovalIn: NSRect(x: 20, y: 20, width: 44, height: 44)).fill()
            ("DESIGN REFERENCE" as NSString).draw(at: NSPoint(x: 16, y: 76), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.darkGray])
            return true
        }
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityIdentifier(card ? "source-card" : "source-image")
        setAccessibilityLabel(card ? "Synthetic text card" : "Synthetic image")
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        preview.draw(in: NSRect(x: 0, y: 0, width: 160, height: 100))
        ((card ? "拖动这张文字卡片" : "拖动这张图片") as NSString).draw(at: NSPoint(x: 0, y: 112), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray])
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        let item = NSPasteboardItem()
        if card { item.setString("卡片参考：使用蓝色建立视觉层级，保留清晰的来源与备注。", forType: .string) }
        else {
            let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
            item.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png)
        }
        let dragged = NSDraggingItem(pasteboardWriter: item)
        dragged.setDraggingFrame(NSRect(x: 0, y: 0, width: 160, height: 100), contents: preview)
        beginDraggingSession(with: [dragged], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let screen = NSScreen.main!
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
window.title = "Mouse Companion · Folder Drag Fixture"; window.backgroundColor = NSColor(srgbRed: 0.97, green: 0.98, blue: 1, alpha: 1)
let image = SourceView(card: false), card = SourceView(card: true)
image.frame = NSRect(x: 70, y: screen.frame.height - 250, width: 200, height: 140)
card.frame = NSRect(x: 310, y: screen.frame.height - 250, width: 200, height: 140)
window.contentView?.addSubview(image); window.contentView?.addSubview(card)
window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true); app.run()

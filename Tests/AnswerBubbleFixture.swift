// Synthetic native background for response tests; no browser/account content is read.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Mouse Companion · UI Fixture"
window.isReleasedWhenClosed = false
let caption = NSTextField(labelWithString: "回答气泡测试素材 · 此处没有选中文字")
caption.font = .systemFont(ofSize: 20)
caption.frame = NSRect(x: 36, y: 120, width: 530, height: 40)
window.contentView?.addSubview(caption)
window.center(); window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()

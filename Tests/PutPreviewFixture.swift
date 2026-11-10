// Run only after focusing the compact tray. Restores the original clipboard after paste.
import AppKit
import CoreGraphics

let pb = NSPasteboard.general
let saved = (pb.pasteboardItems ?? []).map { item in
    item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
        guard let data = item.data(forType: type) else { return nil }
        return (type, data)
    }
}
pb.clearContents()
var selectionTab: Int32?
if CommandLine.arguments.dropFirst().first == "--selection" {
    var error: NSDictionary?
    let create = NSAppleScript(source: "tell application \"Google Chrome\"\nactivate\nset t to make new tab at end of tabs of front window with properties {URL:\"https://example.com\"}\nset active tab index of front window to count of tabs of front window\nreturn id of t\nend tell")?.executeAndReturnError(&error)
    selectionTab = create?.int32Value
    var ready = false
    for _ in 0..<30 {
        usleep(200000)
        error = nil
        let result = NSAppleScript(source: "tell application \"Google Chrome\" to execute active tab of front window javascript \"(() => {const p=document.querySelector('p');if(!p)return false;const r=document.createRange();r.selectNodeContents(p);const s=getSelection();s.removeAllRanges();s.addRange(r);return s.toString().length>20;})()\"")?.executeAndReturnError(&error)
        if result?.booleanValue == true, error == nil { ready = true; break }
    }
    guard ready else { fatalError("Selection fixture did not load") }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: down)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
    }
    usleep(500000)
    _ = NSAppleScript(source: "tell application \"System Events\" to tell process \"Mouse Companion\"\nrepeat with w in windows\nrepeat with b in buttons of w\nif description of b contains \"灵感托盘\" then\nperform action \"AXPress\" of b\nreturn true\nend if\nend repeat\nend repeat\nend tell")?.executeAndReturnError(&error)
} else if CommandLine.arguments.dropFirst().first == "--image" {
    let image = NSImage(size: NSSize(width: 120, height: 80))
    image.lockFocus()
    NSColor.systemIndigo.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 120, height: 80)).fill()
    NSColor.systemYellow.setFill()
    NSBezierPath(ovalIn: NSRect(x: 40, y: 20, width: 40, height: 40)).fill()
    image.unlockFocus()
    pb.setData(image.tiffRepresentation!, forType: .tiff)
} else if CommandLine.arguments.dropFirst().first == "--text" {
    pb.setString(CommandLine.arguments.dropFirst(2).first ?? "访谈摘录：第一次使用时没有发现保存按钮。", forType: .string)
} else {
    pb.setString(CommandLine.arguments.dropFirst().first ?? "https://example.com", forType: .URL)
    if CommandLine.arguments.count > 2 { pb.setString(CommandLine.arguments[2], forType: NSPasteboard.PasteboardType("public.url-name")) }
}
for down in [true, false] {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
    event?.flags = .maskCommand
    event?.post(tap: .cghidEventTap)
}
usleep(700000)
pb.clearContents()
pb.writeObjects(saved.map { fields -> NSPasteboardItem in
    let item = NSPasteboardItem()
    for (type, data) in fields { item.setData(data, forType: type) }
    return item
})
if let selectionTab {
    usleep(2500000)
    var error: NSDictionary?
    _ = NSAppleScript(source: "tell application \"Google Chrome\" to close tab id \(selectionTab) of front window")?.executeAndReturnError(&error)
}

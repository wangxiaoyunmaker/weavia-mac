import AppKit
import ApplicationServices
import CoreGraphics

let pid = pid_t(CommandLine.arguments[1])!
let root = AXUIElementCreateApplication(pid)
let pasteboard = NSPasteboard.general
let savedClipboard = (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } }
defer {
    pasteboard.clearContents()
    pasteboard.writeObjects(savedClipboard.map { values -> NSPasteboardItem in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item })
}
func get(_ e: AXUIElement, _ key: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, key as CFString, &v); return v }
func all(_ e: AXUIElement) -> [AXUIElement] { [e] + (get(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap(all) }
func byID(_ id: String) -> AXUIElement? { all(root).first { get($0, kAXIdentifierAttribute) as? String == id } }
func wait(_ t: Double = 0.15) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
func until(_ condition: () -> Bool) { let end = Date().addingTimeInterval(12); while !condition() && Date() < end { wait() }; if !condition() { print("Current tray frame:", trayFrame()); print("Current IDs:", all(root).compactMap { get($0, kAXIdentifierAttribute) as? String }.filter { $0.hasPrefix("tray-") }); print("Answer value:", answerText()); print("Answer windows:", all(root).filter { get($0, kAXRoleAttribute) as? String == "AXWindow" }.compactMap { get($0, kAXTitleAttribute) as? String }); fflush(stdout) }; precondition(condition(), "UI condition not reached") }
func pressID(_ id: String) { AXUIElementPerformAction(byID(id)!, kAXPressAction as CFString); wait() }
func menu(_ title: String) { let item = all(root).first { get($0, kAXRoleAttribute) as? String == "AXMenuItem" && get($0, kAXTitleAttribute) as? String == title }!; AXUIElementPerformAction(item, kAXPressAction as CFString); wait() }
func answerText() -> String { byID("companion-answer-text").flatMap { get($0, kAXValueAttribute) as? String } ?? "" }
func answerSize() -> CGSize {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
    let window = windows.first { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) && $0[kCGWindowName as String] as? String == "鼠标伙伴回答" }!
    let bounds = window[kCGWindowBounds as String] as! [String: Double]
    return CGSize(width: bounds["Width"]!, height: bounds["Height"]!)
}
func snapshot(_ name: String) {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
    let window = windows.first { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) && $0[kCGWindowName as String] as? String == "鼠标伙伴回答" }!
    let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-l", String(describing: window[kCGWindowNumber as String]!), "/tmp/mouse-companion-answer-" + name + ".png"]
    do { try capture.run(); capture.waitUntilExit() } catch { print("Screenshot unavailable: \(error.localizedDescription)") }
}
func send(_ text: String, ending: String) {
    print("ANSWER UI request:", text); fflush(stdout)
    AXUIElementSetAttributeValue(byID("companion-prompt")!, kAXValueAttribute as CFString, text as CFString)
    pressID("companion-send")
    until { answerText().contains(ending) }
    print("ANSWER UI received:", text, answerSize()); fflush(stdout)
}
let sourcePID = pid_t(CommandLine.arguments[2])!
let sourceRoot = AXUIElementCreateApplication(sourcePID)
func frame(_ e: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(get(e, kAXPositionAttribute) as! AXValue, .cgPoint, &p)
    AXValueGetValue(get(e, kAXSizeAttribute) as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func trayFrame() -> CGRect {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
    let w = windows.first { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) && $0[kCGWindowName as String] as? String == "灵感托盘" }!
    let b = w[kCGWindowBounds as String] as! [String: Double]
    return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
}
func move(_ point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    wait(0.2)
}
func mouse(_ type: CGEventType, _ point: CGPoint) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventClickState, value: 1); e.flags = []; e.post(tap: .cghidEventTap)
}
func shot(_ name: String) {
    let r = trayFrame(), maxX = NSScreen.main!.frame.maxX
    let width = min(r.width, maxX - r.minX)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(width)),\(Int(r.height))", "/tmp/mouse-companion-folder-\(name).png"]
    try! p.run(); p.waitUntilExit()
}
let edge = NSScreen.main!.frame.maxX
until { byID("tray-folder") != nil }
move(CGPoint(x: edge - 240, y: trayFrame().midY))
precondition(trayFrame().width == 112 && trayFrame().minX >= edge - 33)
shot("docked")
move(CGPoint(x: edge - 10, y: trayFrame().midY))
until { trayFrame().maxX <= edge + 1 && trayFrame().minX < edge - 100 }
shot("closed")
move(CGPoint(x: edge - 240, y: trayFrame().midY)); wait(1.1)
precondition(trayFrame().minX >= edge - 33, "Hover exit did not retract the folder")
func dragSource(_ id: String, captureOpening: Bool = false) {
    NSRunningApplication(processIdentifier: sourcePID)!.activate(options: [])
    wait(0.2)
    until { all(sourceRoot).contains { get($0, kAXIdentifierAttribute) as? String == id } }
    let source = all(sourceRoot).first { get($0, kAXIdentifierAttribute) as? String == id }!
    let r = frame(source)
    let start = CGPoint(x: r.minX + 80, y: r.minY + 50)
    move(start); mouse(.leftMouseDown, start); wait(0.1)
    for i in 1...3 { mouse(.leftMouseDragged, CGPoint(x: start.x + Double(i) * 5, y: start.y)); wait(0.02) }
    wait(0.12)
    if captureOpening {
        shot("opening"); wait(0.4); shot("open")
        let closed = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: "/tmp/mouse-companion-folder-closed.png")))!
        let opened = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: "/tmp/mouse-companion-folder-open.png")))!
        let c = closed.colorAt(x: 108, y: 44)!.usingColorSpace(.sRGB)!
        let o = opened.colorAt(x: 108, y: 44)!.usingColorSpace(.sRGB)!
        print("Folder card pixel closed/open:", c.redComponent, o.redComponent); fflush(stdout)
        precondition(o.redComponent > c.redComponent + 0.03, "Dragging never lifted the cards / opened the folder")
    }
    let target = CGPoint(x: trayFrame().midX, y: trayFrame().minY + 48)
    for i in 1...24 {
        let point = CGPoint(x: start.x + (target.x - start.x) * Double(i) / 24, y: start.y + (target.y - start.y) * Double(i) / 24)
        CGWarpMouseCursorPosition(point); mouse(.leftMouseDragged, point); wait(0.025)
    }
    mouse(.leftMouseUp, target)
    wait(0.3)
    until { byID("tray-note") != nil }
}
dragSource("source-image", captureOpening: true)
precondition(trayFrame().width == 430)
precondition(all(root).contains { get($0, kAXDescriptionAttribute) as? String == "放大图片" })
AXUIElementSetAttributeValue(byID("tray-note")!, kAXValueAttribute as CFString, "文件夹收起后保留的想法" as CFString)
pressID("tray-minimize")
until { byID("tray-folder") != nil && trayFrame().minX >= edge - 33 }
move(CGPoint(x: edge - 10, y: trayFrame().midY))
until { byID("tray-note") != nil }
precondition(get(byID("tray-note")!, kAXValueAttribute) as? String == "文件夹收起后保留的想法", "Minimize lost the current material note")
print("PASS: hover restored minimized image and its note"); fflush(stdout)
pressID("tray-close")
until { byID("tray-folder") != nil }
dragSource("source-card")
precondition(all(root).contains { (get($0, kAXValueAttribute) as? String ?? "").contains("卡片参考") })
print("PASS: actual cross-app PNG and text-card drops into the animated folder"); fflush(stdout)
pressID("tray-close")
move(CGPoint(x: edge - 10, y: trayFrame().midY))
until { trayFrame().minX < edge - 100 }
shot("collected")
pressID("tray-folder-minimize")
until { trayFrame().minX >= edge - 33 }
// Clicking opens the real collection, with previews, details and filters.
pressID("tray-folder")
until { byID("tray-contents") != nil }
func materialRows() -> [AXUIElement] { all(root).filter { (get($0, kAXIdentifierAttribute) as? String ?? "").hasPrefix("tray-material-") } }
precondition(materialRows().count == 2)
shot("contents")
let textRow = materialRows().first { (get($0, kAXDescriptionAttribute) as? String ?? "").contains("卡片参考") }!
let textID = get(textRow, kAXIdentifierAttribute) as! String
pressID(textID)
until { byID("tray-note") != nil }
AXUIElementSetAttributeValue(byID("tray-note")!, kAXValueAttribute as CFString, "从列表继续整理的备注" as CFString)
pressID("tray-back")
until { byID("tray-contents") != nil }
pressID(textID)
precondition(get(byID("tray-note")!, kAXValueAttribute) as? String == "从列表继续整理的备注")
let save = all(root).first { get($0, kAXTitleAttribute) as? String == "放入画布  →" }!
AXUIElementPerformAction(save, kAXPressAction as CFString); wait(0.3)
pressID("tray-folder")
until { byID("tray-contents") != nil }
func filter(_ index: Int) {
    let r = frame(byID("tray-contents-filter")!), p = CGPoint(x: r.minX + r.width * (Double(index) + 0.5) / 3, y: r.midY)
    move(p); mouse(.leftMouseDown, p); mouse(.leftMouseUp, p); wait(0.3)
}
filter(2)
precondition(materialRows().count == 1 && (get(materialRows()[0], kAXDescriptionAttribute) as? String ?? "").contains("已入画布"))
filter(1)
precondition(materialRows().count == 1 && (get(materialRows()[0], kAXDescriptionAttribute) as? String ?? "").contains("待整理"))
filter(0)
precondition(materialRows().count == 2)
let preview = all(root).first { (get($0, kAXIdentifierAttribute) as? String ?? "").hasPrefix("tray-preview-") && get($0, kAXDescriptionAttribute) as? String == "放大图片" }!
AXUIElementPerformAction(preview, kAXPressAction as CFString); wait(0.3)
let previewWindow = (get(root, kAXWindowsAttribute) as! [AXUIElement]).first { get($0, kAXTitleAttribute) as? String != "灵感托盘" && all($0).contains { get($0, kAXSubroleAttribute) as? String == "AXCloseButton" } && !(get($0, kAXTitleAttribute) as? String ?? "").hasPrefix("Project Canvas") }!
let previewClose = all(previewWindow).first { get($0, kAXSubroleAttribute) as? String == "AXCloseButton" }!
AXUIElementPerformAction(previewClose, kAXPressAction as CFString); wait(0.2)
pressID("tray-minimize")
until { byID("tray-folder") != nil }
move(CGPoint(x: edge - 10, y: trayFrame().midY))
until { byID("tray-contents") != nil }
precondition(materialRows().count == 2)
pressID("tray-close")
until { byID("tray-folder") != nil }
print("PASS: click opens contents, real thumbnail preview, edit/back retains notes, pending/saved filters and minimized list restoration"); fflush(stdout)
// Preserve the existing external Cmd+C -> folder click -> Cmd+V workflow.
pasteboard.clearContents(); pasteboard.setString("文件夹文字粘贴验收", forType: .string)
NSRunningApplication(processIdentifier: sourcePID)!.activate(options: []); wait(0.2)
for down in [true, false] { let event = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: down); event?.flags = .maskCommand; event?.post(tap: .cghidEventTap) }
wait(1.8)
move(CGPoint(x: edge - 10, y: trayFrame().midY))
wait(0.3)
let folder = frame(byID("tray-folder")!), click = CGPoint(x: min(edge - 16, folder.midX), y: folder.minY + 48)
move(click); mouse(.leftMouseDown, click); mouse(.leftMouseUp, click); wait(0.3)
until { byID("tray-contents") != nil }
for down in [true, false] { let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down); event?.flags = .maskCommand; event?.post(tap: .cghidEventTap) }
until { byID("tray-note") != nil }
precondition(all(root).contains { (get($0, kAXValueAttribute) as? String ?? "").contains("文件夹文字粘贴验收") })
print("PASS: external copy, click folder, and native Cmd+V collect a new text material despite older pending materials")
pressID("tray-back")
until { byID("tray-contents") != nil }
dragSource("source-image")
precondition(all(root).contains { get($0, kAXDescriptionAttribute) as? String == "放大图片" })
print("PASS: additional image dropped directly into the open contents list")
print("PASS: edge peek, hover retraction, folder open/close, explicit compact collapse, and retained pending material")
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())

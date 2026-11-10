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
func until(_ condition: () -> Bool) { let end = Date().addingTimeInterval(12); while !condition() && Date() < end { wait() }; if !condition() { print("Answer value:", answerText()); print("Answer windows:", all(root).filter { get($0, kAXRoleAttribute) as? String == "AXWindow" }.compactMap { get($0, kAXTitleAttribute) as? String }); fflush(stdout) }; precondition(condition(), "UI condition not reached") }
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
func pressTitle(_ title: String) {
    let control = all(root).first { get($0, kAXTitleAttribute) as? String == title && get($0, kAXRoleAttribute) as? String == "AXButton" }!
    AXUIElementPerformAction(control, kAXPressAction as CFString); wait()
}
func hasText(_ text: String) -> Bool { all(root).contains { (get($0, kAXValueAttribute) as? String ?? "").contains(text) || (get($0, kAXTitleAttribute) as? String ?? "").contains(text) } }
import CoreGraphics
let x = Double(CommandLine.arguments[2])!, y = Double(CommandLine.arguments[3])!
let start = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(start)
let source = CGEventSource(stateID: .combinedSessionState)
func mouse(_ type: CGEventType, _ point: CGPoint) { let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!; e.flags = []; e.setIntegerValueField(.mouseEventClickState, value: 1); e.post(tap: .cghidEventTap) }
mouse(.mouseMoved, start); wait(0.3); mouse(.leftMouseDown, start); wait(0.2)
for i in 1...4 { mouse(.leftMouseDragged, CGPoint(x: x - Double(i) * 4, y: y + Double(i))); wait(0.03) }
wait(0.4)
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
let tray = windows.first { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) && $0[kCGWindowName as String] as? String == "灵感托盘" }!
let b = tray[kCGWindowBounds as String] as! [String: Double]
let target = CGPoint(x: min(NSScreen.main!.frame.maxX - 20, b["X"]! + 56), y: b["Y"]! + 48)
for i in 1...35 {
    let point = CGPoint(x: x + (target.x - x) * Double(i) / 35, y: y + (target.y - y) * Double(i) / 35)
    CGWarpMouseCursorPosition(point); mouse(.leftMouseDragged, point); wait(0.025)
}
mouse(.leftMouseUp, target)
until { byID("tray-note-body") != nil && hasText("已读取笔记正文") }
until { hasText("复用三步访谈结构") }
pressID("tray-note-body")
until { hasText("BROWSER_NOTE_BODY_SENTINEL") }
print("PASS: actual Chrome link drag captured DOM body with cover, delivered body to suggestion request, and exposed captured body preview")
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())

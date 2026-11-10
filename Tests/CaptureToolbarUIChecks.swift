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
func frame(_ element: AXUIElement) -> CGRect {
    var point = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(get(element, kAXPositionAttribute) as! AXValue, .cgPoint, &point)
    AXValueGetValue(get(element, kAXSizeAttribute) as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}
func move(_ point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    wait(0.25)
}
func mouse(_ type: CGEventType, _ point: CGPoint) {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
    event.setIntegerValueField(.mouseEventClickState, value: 1); event.post(tap: .cghidEventTap); wait(0.2)
}
func capture(_ name: String) {
    let r = frame(byID("capture-toolbar")!)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))", "/tmp/mouse-companion-toolbar-\(name).png"]
    try! p.run(); p.waitUntilExit()
}
menu("和鼠标伙伴对话（/）")
until { byID("capture-toolbar") != nil }
wait(0.4)
let ids = ["capture-tool-0", "capture-tool-1", "capture-tool-2", "capture-undo", "capture-save", "capture-collect", "capture-context", "capture-close"]
for id in ids {
    let r = frame(byID(id)!)
    print("ICON FRAME", id, r); fflush(stdout)
    precondition(r.height == 32 && (id == "capture-context" ? r.width >= 46 : r.width == 32), "Icon click regions must be square except the compound context button")
}
let selected = frame(byID("capture-tool-0")!)
let ordinary = frame(byID("capture-tool-1")!)
move(CGPoint(x: selected.minX, y: selected.maxY + 100)); capture("normal")
move(CGPoint(x: selected.midX, y: selected.midY)); capture("selected-hover")
mouse(.leftMouseDown, CGPoint(x: selected.midX, y: selected.midY)); capture("selected-pressed")
mouse(.leftMouseUp, CGPoint(x: selected.midX, y: selected.midY))
move(CGPoint(x: ordinary.midX, y: ordinary.midY)); capture("hover")
mouse(.leftMouseDown, CGPoint(x: ordinary.midX, y: ordinary.midY)); capture("pressed")
mouse(.leftMouseUp, CGPoint(x: ordinary.midX, y: ordinary.midY))
precondition(get(byID("capture-tool-1")!, kAXSelectedAttribute) as? Bool == true)
precondition(get(byID("capture-tool-0")!, kAXSelectedAttribute) as? Bool == false)
move(CGPoint(x: ordinary.minX, y: ordinary.maxY + 100)); capture("selected")
let context = byID("capture-context")!, compound = frame(context)
precondition((get(context, kAXChildrenAttribute) as? [AXUIElement] ?? []).isEmpty, "Count must belong to the same accessible button")
let number = CGPoint(x: compound.maxX - 10, y: compound.midY)
move(number); capture("context-hover")
mouse(.leftMouseDown, number); capture("context-pressed")
mouse(.leftMouseUp, number)
until { all(root).contains { get($0, kAXTitleAttribute) as? String == "鼠标伙伴 · 共享上下文" } }
print("PASS: square icon geometry, persistent exclusive selection after mouse release, real hover/press snapshots, and clicking the number opens the compound context control")
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())

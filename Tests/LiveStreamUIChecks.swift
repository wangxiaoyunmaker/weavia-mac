import AppKit
import ApplicationServices
import CoreGraphics

precondition(ProcessInfo.processInfo.environment["MOUSE_COMPANION_LIVE_API_CHECK"] == "1", "Live API checks require explicit opt-in; use local fixtures for normal tests")
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
menu("和鼠标伙伴对话（/）")
until { byID("companion-prompt") != nil }
wait(0.6)
AXUIElementSetAttributeValue(byID("companion-prompt")!, kAXValueAttribute as CFString, "请分成五个短段落，介绍设计中的视觉层级，每段两句话，不要读取或处理任何界面内容。" as CFString)
pressID("companion-send")
var samples: [String] = []
let deadline = Date().addingTimeInterval(55)
var completed = false
while Date() < deadline {
    let text = answerText()
    let statuses = all(root).compactMap { get($0, kAXValueAttribute) as? String }
    if !text.isEmpty && samples.last != text { samples.append(text); print("LIVE progress characters:", text.count, "size:", answerSize()); fflush(stdout) }
    if statuses.contains("已完成") { completed = true; break }
    if statuses.contains("未完成") { print("LIVE error:", text); fflush(stdout); break }
    wait(0.12)
}
print("LIVE RESULT completed:", completed, "distinct updates:", samples.count); fflush(stdout)
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())
precondition(completed && samples.count > 1, "Configured endpoint did not deliver incremental text")

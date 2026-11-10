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
menu("显示灵感托盘")
until { byID("tray-material-11111111-1111-4111-8111-111111111111") != nil }
pressID("tray-material-11111111-1111-4111-8111-111111111111")
until { byID("tray-note-body") != nil && hasText("已读取笔记正文") }
pressID("tray-note-body")
until { hasText("NOTE_BODY_SENTINEL") }
let windows = get(root, kAXWindowsAttribute) as! [AXUIElement]
let preview = windows.first { (get($0, kAXTitleAttribute) as? String ?? "").hasSuffix("采集正文") }!
let close = all(preview).first { get($0, kAXSubroleAttribute) as? String == "AXCloseButton" }!
AXUIElementPerformAction(close, kAXPressAction as CFString); wait()
pressTitle("重新生成")
until { hasText("提取三步访谈结构") && hasText("比较先试用后追问") }
print("PASS: restored webpage image retains real body; body preview and content-based AI suggestions work"); fflush(stdout)
pressID("tray-back")
pressID("tray-material-22222222-2222-4222-8222-222222222222")
until { hasText("未读取笔记正文") }
pressTitle("重新生成")
until { hasText("补读笔记正文") && hasText("仅有封面和 OCR") }
precondition(!hasText("NOTE_BODY_SENTINEL"), "Wrong note body appeared in the cover-only material")
print("PASS: old cover/OCR material is not mislabeled as note body and missing-body boundary is visible")
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())

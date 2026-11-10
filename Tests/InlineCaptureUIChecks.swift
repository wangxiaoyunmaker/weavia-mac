// Exercise the packaged app against a synthetic browser page and a local API fixture.
import AppKit
import ApplicationServices
import CoreGraphics

let pid = pid_t(CommandLine.arguments[1])!
let geometry = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String: Double]]
let root = AXUIElementCreateApplication(pid)
func get(_ e: AXUIElement, _ key: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, key as CFString, &v); return v }
func all(_ e: AXUIElement) -> [AXUIElement] { [e] + (get(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap(all) }
func wait(_ seconds: Double = 0.25) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
func strings() -> [String] { all(root).flatMap { [get($0, kAXTitleAttribute) as? String, get($0, kAXValueAttribute) as? String].compactMap { $0 } } }
func press(_ title: String, role: String = "AXButton") {
    let ids = ["撤销": "capture-undo", "放入托盘": "capture-collect", "结束圈画 Esc": "capture-close", "保存选区": "capture-save"]
    guard let button = all(root).first(where: { get($0, kAXRoleAttribute) as? String == role && (get($0, kAXTitleAttribute) as? String == title || (ids[title] != nil && get($0, kAXIdentifierAttribute) as? String == ids[title])) }) else { fatalError("Missing control: \(title)") }
    AXUIElementPerformAction(button, kAXPressAction as CFString); wait()
}
func waitFor(_ predicate: () -> Bool) {
    let end = Date().addingTimeInterval(12)
    while !predicate() && Date() < end { wait(0.1) }
    precondition(predicate(), "UI condition not reached")
}
func assertMode() {
    precondition(strings().contains("圈画上下文"), "Sending left annotation mode")
    precondition(strings().contains("退出灵感模式"), "Inspiration mode was disabled")
}
func prompt() -> AXUIElement {
    all(root).first { get($0, kAXIdentifierAttribute) as? String == "companion-prompt" && get($0, kAXRoleAttribute) as? String == "AXTextField" }!
}
func send(_ text: String) {
    print("UI send:", text); fflush(stdout)
    precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, "Test app lost keyboard focus")
    let chars = Array(text.utf16)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
        chars.withUnsafeBufferPointer { event?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: $0.baseAddress!) }
        event?.post(tap: .cghidEventTap)
    }
    let keyboardDeadline = Date().addingTimeInterval(2)
    while get(prompt(), kAXValueAttribute) as? String != text && Date() < keyboardDeadline { wait(0.1) }
    if get(prompt(), kAXValueAttribute) as? String != text {
        let focused = get(root, kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
        print("Keyboard focus:", focused.flatMap { get($0, kAXRoleAttribute) as? String } ?? "none", focused.flatMap { get($0, kAXIdentifierAttribute) as? String } ?? "none", "prompt value:", get(prompt(), kAXValueAttribute) as? String ?? "nil"); fflush(stdout)
    }
    precondition(get(prompt(), kAXValueAttribute) as? String == text, "Drawing did not return real keyboard input to the prompt")
    for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: down)?.post(tap: .cghidEventTap) }
    wait(0.3)
    assertMode()
    precondition(get(prompt(), kAXValueAttribute) as? String == "", "Prompt did not stay editable for the next message")
}
func byID(_ id: String) -> AXUIElement { all(root).first { get($0, kAXIdentifierAttribute) as? String == id }! }
func chooseMaterial(containing needle: String) {
    AXUIElementPerformAction(byID("tray-material-picker"), kAXPressAction as CFString); wait()
    guard let item = all(root).first(where: { get($0, kAXRoleAttribute) as? String == "AXMenuItem" && (get($0, kAXTitleAttribute) as? String ?? "").contains(needle) }) else { fatalError("Missing collected material: \(needle)") }
    AXUIElementPerformAction(item, kAXPressAction as CFString); wait()
    print("UI choosing material:", needle); fflush(stdout)
}
func draw(_ index: Int) {
    let rect = geometry[index]
    let start = CGPoint(x: rect["x"]! + 4, y: rect["y"]! + 4), end = CGPoint(x: rect["x"]! + rect["w"]! - 4, y: rect["y"]! + rect["h"]! - 4)
    CGWarpMouseCursorPosition(start)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
    for i in 1...16 {
        let point = CGPoint(x: start.x + (end.x-start.x)*Double(i)/16, y: start.y + (end.y-start.y)*Double(i)/16)
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        wait(0.015)
    }
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
    wait(0.3)
}

press("和鼠标伙伴对话（/）", role: "AXMenuItem")
waitFor { strings().contains("圈画上下文") && all(root).contains { get($0, kAXIdentifierAttribute) as? String == "companion-prompt" } }
waitFor { all(root).contains { get($0, kAXIdentifierAttribute) as? String == "capture-selection" } }
draw(0)
send("圈画阶段第一轮：解释这个选区")
draw(1) // A later draft must not enter the first message's snapshot.
waitFor { strings().contains { $0.contains("INLINE_RESPONSE_1") } }
assertMode()
send("圈画阶段第二轮：结合新增选区继续")
waitFor { strings().contains { $0.contains("INLINE_RESPONSE_2") } }
assertMode()

let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
let own = windows.filter { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) }
let drawing = own.first { $0[kCGWindowName as String] as? String == "圈画上下文" }!
let base = drawing[kCGWindowLayer as String] as! Int
precondition(own.contains { w in
    let bounds = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return w[kCGWindowName as String] as? String == "鼠标伙伴回答" && (bounds["Width"] ?? 0) <= 420 && (w[kCGWindowLayer as String] as? Int ?? 0) > base
}, "Agent answer is hidden beneath the drawing overlay")
precondition(own.contains { w in
    let bounds = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return bounds["Height"] == 44 && (w[kCGWindowLayer as String] as? Int ?? 0) > base
}, "Prompt is hidden beneath the drawing overlay")
press("撤销")
send("圈画阶段第三轮：撤销后再追问")
waitFor { strings().contains { $0.contains("INLINE_RESPONSE_3") } }
assertMode()
press("放入托盘")
precondition(all(root).contains { get($0, kAXDescriptionAttribute) as? String == "放大图片" }, "Collected screenshot thumbnail is missing")
precondition(AXUIElementSetAttributeValue(byID("tray-note"), kAXValueAttribute as CFString, "图片备注/保留" as CFString) == .success)
chooseMaterial(containing: "紫色石榴盒")
waitFor { all(root).contains { get($0, kAXDescriptionAttribute) as? String == "查看文字全文" } }
precondition(AXUIElementSetAttributeValue(byID("tray-note"), kAXValueAttribute as CFString, "文字备注" as CFString) == .success)
chooseMaterial(containing: "圈画")
waitFor { get(byID("tray-note"), kAXValueAttribute) as? String == "图片备注/保留" }
press("继续收集")
press("放入托盘")
waitFor { get(byID("tray-note"), kAXValueAttribute) as? String == "图片备注/保留" }
press("继续收集")
press("结束圈画 Esc")
precondition(!strings().contains("圈画上下文") && strings().contains("退出灵感模式"))
var error: NSDictionary?
_ = NSAppleScript(source: "tell application \"Google Chrome\" to execute active tab of front window javascript \"getSelection().removeAllRanges()\"")?.executeAndReturnError(&error)
precondition(error == nil)
press("和鼠标伙伴对话（/）", role: "AXMenuItem")
waitFor { strings().contains { $0.contains("未读到选中文字") } }
send("重新开启后的第四轮：本次没有选择内容")
waitFor { strings().contains { $0.contains("INLINE_RESPONSE_4") } }
assertMode()
press("结束圈画 Esc")
press("查看项目对话记录…", role: "AXMenuItem")
precondition(strings().contains { $0.contains("查看历史附件") && $0.contains("INLINE_RESPONSE_1") })
print("UI PASS: in-mode dialogue and undo; text/image transfer, material switching and notes; a new mode sends no old attachments; history retains original references")
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())

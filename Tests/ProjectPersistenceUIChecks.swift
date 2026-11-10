import AppKit
import ApplicationServices

let pid = pid_t(CommandLine.arguments[1])!
let mode = CommandLine.arguments[2]
let root = AXUIElementCreateApplication(pid)
func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?; AXUIElementCopyAttributeValue(element, name as CFString, &result); return result
}
func all(_ element: AXUIElement) -> [AXUIElement] {
    [element] + (value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap(all)
}
func wait() { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
func menu(_ title: String) {
    guard let item = all(root).first(where: { value($0, kAXRoleAttribute) as? String == "AXMenuItem" && value($0, kAXTitleAttribute) as? String == title }) else { fatalError("Missing menu: \(title)") }
    AXUIElementPerformAction(item, kAXPressAction as CFString); wait()
}
func texts() -> [String] { all(root).flatMap { [value($0, kAXValueAttribute) as? String, value($0, kAXTitleAttribute) as? String].compactMap { $0 } } }

if mode == "first" {
    menu("查看共享上下文…")
    precondition(texts().contains { $0.contains("30 份素材及 42 条会话") })
    precondition(texts().contains { $0.contains("本轮 0 份选区") })
    menu("打开项目画布")
    precondition(texts().contains { $0.contains("29 份素材") })
    menu("查看项目对话记录…")
    precondition(texts().contains { $0.contains("完整对话 39") && $0.contains("榴莲约束：先验证再采纳") })
    precondition(texts().contains { $0.contains("圈画与原文") })
    menu("显示灵感托盘")
    let pending = all(root).first { (value($0, kAXIdentifierAttribute) as? String ?? "").hasPrefix("tray-material-") && (value($0, kAXDescriptionAttribute) as? String ?? "").contains("待整理") }!
    AXUIElementPerformAction(pending, kAXPressAction as CFString); wait()
    let fields = all(root).filter { value($0, kAXRoleAttribute) as? String == "AXTextField" }
    guard let note = fields.first(where: { value($0, kAXValueAttribute) as? String == "个人想法 29" }) else { fatalError("Tray note was not restored") }
    let checkboxes = all(root).filter { value($0, kAXRoleAttribute) as? String == "AXCheckBox" }
    precondition(checkboxes.contains { (value($0, kAXValueAttribute) as? NSNumber)?.intValue == 1 }, "Accepted suggestions not restored")
    precondition(AXUIElementSetAttributeValue(note, kAXValueAttribute as CFString, "重启后仍保留的新想法" as CFString) == .success)
    print("UI PASS: real app restored project, region, 29 canvas cards, full history, pending tray and accepted suggestion")
} else if mode == "second" {
    menu("显示灵感托盘")
    let pending = all(root).first { (value($0, kAXIdentifierAttribute) as? String ?? "").hasPrefix("tray-material-") && (value($0, kAXDescriptionAttribute) as? String ?? "").contains("待整理") }!
    AXUIElementPerformAction(pending, kAXPressAction as CFString); wait()
    precondition(texts().contains("重启后仍保留的新想法"), "Quit did not save the edited tray note")
    menu("查看项目对话记录…")
    precondition(texts().contains { $0.contains("完整对话 39") })
    print("UI PASS: after a real app quit/relaunch, edited tray note and conversation were retained")
}
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())

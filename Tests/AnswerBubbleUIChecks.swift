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
menu("和鼠标伙伴对话（/）")
until { byID("companion-prompt") != nil }
let toolbarIDs = ["capture-tool-0", "capture-tool-1", "capture-tool-2", "capture-undo", "capture-save", "capture-collect", "capture-context", "capture-close"]
for id in toolbarIDs {
    let control = byID(id)!
    precondition((get(control, kAXTitleAttribute) as? String ?? "").isEmpty, "Toolbar contains a visible text button")
    precondition(!(get(control, kAXHelpAttribute) as? String ?? "").isEmpty, "Toolbar icon has no hover help")
}
precondition(!all(root).contains { (get($0, kAXTitleAttribute) as? String ?? "").contains("粘贴文字") })
if let bar = byID("capture-toolbar"), let value = get(bar, kAXSizeAttribute) {
    var size = CGSize.zero; AXValueGetValue(value as! AXValue, .cgSize, &size)
    precondition(size.height <= 52, "Toolbar is still several rows tall")
    print("TOOLBAR UI:", size); fflush(stdout)
    if let v = get(bar, kAXPositionAttribute) {
        var pos = CGPoint.zero; AXValueGetValue(v as! AXValue, .cgPoint, &pos)
        let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-R", "\(Int(pos.x)),\(Int(pos.y)),\(Int(size.width)),\(Int(size.height))", "/tmp/mouse-companion-capture-toolbar.png"]
        try! capture.run(); capture.waitUntilExit()
    }
}
wait(0.5)
send("short", ending: "短答：你好。")
let short = answerSize()
snapshot("short")
precondition(short.width <= 260 && short.height < 100, "Short response still occupies a large fixed card")
pressID("answer-copy")
precondition(pasteboard.string(forType: .string) == "短答：你好。")
send("medium", ending: "自然变宽的回答。")
let medium = answerSize()
precondition(medium.width > short.width, "Bubble did not grow with text")
send("long", ending: "最后一行：复制验收")
let expanded = answerSize()
snapshot("long")
precondition(expanded.width <= 420 && expanded.height <= 360 && expanded.height > medium.height)
pressID("answer-copy")
let complete = pasteboard.string(forType: .string)!
precondition(complete.hasPrefix("长回答标题") && complete.contains("最后一行：复制验收") && complete.count > 2000)
precondition(!complete.hasPrefix("# "))
pressID("answer-collapse")
precondition(answerSize().height == 36 && answerSize().width < expanded.width)
snapshot("collapsed")
pressID("answer-copy")
precondition(pasteboard.string(forType: .string) == complete, "Copying a collapsed answer lost hidden content")
pressID("answer-collapse")
precondition(answerSize() == expanded && answerText() == complete, "Expanding did not restore the complete answer")
pressID("answer-history")
print("ANSWER UI history"); fflush(stdout)
until { all(root).contains { (get($0, kAXTitleAttribute) as? String ?? "").hasSuffix(" · 对话记录") } }
let history = all(root).first { (get($0, kAXTitleAttribute) as? String ?? "").hasSuffix(" · 对话记录") && get($0, kAXRoleAttribute) as? String == "AXWindow" }!
precondition(all(history).contains { (get($0, kAXValueAttribute) as? String ?? "").contains("最后一行：复制验收") })
let close = all(history).first { get($0, kAXSubroleAttribute) as? String == "AXCloseButton" }!
AXUIElementPerformAction(close, kAXPressAction as CFString); wait()
// REAL mouse dragging, both above the drawing overlay and after it closes.
func dragCopy() {
    wait(0.4)
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
    let w = windows.first { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) && $0[kCGWindowName as String] as? String == "鼠标伙伴回答" }!
    let b = w[kCGWindowBounds as String] as! [String: Double]
    let start = CGPoint(x: b["X"]! + 13, y: b["Y"]! + 47)
    CGWarpMouseCursorPosition(start)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)!
    down.setIntegerValueField(.mouseEventClickState, value: 1); down.post(tap: .cghidEventTap)
    wait(0.12)
    for step in 1...12 {
        let point = CGPoint(x: start.x + Double(step) * 2.5, y: start.y)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap); wait(0.025)
    }
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: start.x + 30, y: start.y), mouseButton: .left)?.post(tap: .cghidEventTap)
    wait(0.2)
    let selected = get(byID("companion-answer-text")!, kAXSelectedTextAttribute) as? String ?? ""
    print("REAL DRAG selected:", selected); fflush(stdout)
    precondition(!selected.isEmpty && selected.count < answerText().count, "Physical mouse drag did not select a partial answer")
    for down in [true, false] { let event = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: down); event?.flags = .maskCommand; event?.post(tap: .cghidEventTap) }
    until { pasteboard.string(forType: .string) == selected }
    print("REAL DRAG copy passed"); fflush(stdout)
}
// Observe content while the server is still generating, not a typewriter replay.
AXUIElementSetAttributeValue(byID("companion-prompt")!, kAXValueAttribute as CFString, "stream" as CFString)
pressID("companion-send")
until { answerText().contains("流式输出。") }
precondition(!answerText().contains("最后一行：流式验收"))
let firstChunkSize = answerSize()
snapshot("stream-first")
dragCopy()
let frozenText = answerText()
let frozenSize = answerSize()
wait(1.4)
precondition(answerText() == frozenText && answerSize() == frozenSize, "Streaming replaced text or moved the bubble while selected")
// Deselect using a real click; pending output becomes visible again.
let responseWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
let response = responseWindows.first { $0[kCGWindowOwnerPID as String] as? Int == Int(pid) && $0[kCGWindowName as String] as? String == "鼠标伙伴回答" }!
let responseBounds = response[kCGWindowBounds as String] as! [String: Double]
let point = CGPoint(x: responseBounds["X"]! + 125, y: responseBounds["Y"]! + 47)
CGWarpMouseCursorPosition(point)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
wait(0.2)
for type in [CGEventType.leftMouseDown, .leftMouseUp] { let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!; e.setIntegerValueField(.mouseEventClickState, value: 1); e.post(tap: .cghidEventTap); wait(0.05) }
print("After deselect:", get(byID("companion-answer-text")!, kAXSelectedTextAttribute) as? String ?? "nil"); fflush(stdout)
until { answerText().contains("最后一行：流式验收") }
precondition(answerSize().height > firstChunkSize.height)
print("STREAM UI PASS: partial content visible before final event, progressive sizing, physical drag copy during generation and selection stability"); fflush(stdout)
snapshot("stream-final")
send("broken", ending: "生成中断：")
precondition(answerText().hasPrefix("这是一段已经生成的内容。") && answerText().contains("连接已中断"))
precondition(all(root).contains { get($0, kAXValueAttribute) as? String == "未完成" })
pressID("answer-copy")
precondition((pasteboard.string(forType: .string) ?? "").hasPrefix("这是一段已经生成的内容。"))
send("medium", ending: "自然变宽的回答。")
dragCopy()
pressID("capture-close")
dragCopy()
precondition(!all(root).contains { get($0, kAXValueAttribute) as? String == "灵感托盘" }, "Copying an answer unexpectedly opened collection UI")
print("UI PASS: short/medium/long sizes, collapse/expand, full-copy while collapsed, history button, Markdown display and native selected-text Cmd+C")
precondition(NSRunningApplication(processIdentifier: pid)!.terminate())

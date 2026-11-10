// Explicit native UI exercise. Uses only this synthetic page and restores the browser tab.
import AppKit
import CoreGraphics

func script(_ source: String) -> String {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error { print("UI script error: \(error[NSAppleScript.errorMessage] ?? "unknown")") }
    return result?.stringValue ?? ""
}
func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\"" }
func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down); e?.flags = flags; e?.post(tap: .cghidEventTap) }
}
func text(_ value: String) {
    let chars = Array(value.utf16)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
        chars.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: $0.baseAddress!) }; e?.post(tap: .cghidEventTap)
    }
}
let statePath = "/tmp/mouse-companion-context-ui.json"
let mode = CommandLine.arguments.dropFirst().first ?? "inspect"
if mode == "prepare" {
    let html = """
    <!doctype html><meta charset="utf-8"><title>Mouse Companion 上下文测试</title>
    <style>body{font:20px system-ui;padding:80px 70px;background:#fff}h1{font-size:28px}#selected{max-width:800px;padding:20px;background:#f5f5f5}svg{margin-top:36px;background:#fff;border:1px solid #ddd}</style>
    <h1>共享上下文测试素材</h1><p id="selected">这是一次测试：本项目的盒子名称是「紫色石榴盒」，目标是让新手更容易找到保存入口。</p>
    <svg id="visual" width="350" height="180" viewBox="0 0 350 180"><path fill="#1261ff" d="M35 130 L75 45 L115 130Z M135 130 L175 45 L215 130Z M235 130 L275 45 L315 130Z"/></svg>
    """
    try html.write(toFile: "/tmp/mouse-companion-context-fixture.html", atomically: true, encoding: .utf8)
    let previous = script("tell application \"Google Chrome\" to return active tab index of front window")
    let id = script("tell application \"Google Chrome\"\nactivate\nset t to make new tab at end of tabs of front window with properties {URL:\"file:///tmp/mouse-companion-context-fixture.html\"}\nset active tab index of front window to count of tabs of front window\nreturn id of t\nend tell")
    usleep(1200000)
    let js = "(() => {const p=document.getElementById('selected');if(!p)return '';const r=document.createRange();r.selectNodeContents(p);getSelection().removeAllRanges();getSelection().addRange(r);const b=document.getElementById('visual').getBoundingClientRect();return JSON.stringify({x:screenX+b.x,y:screenY+outerHeight-innerHeight+b.y,w:b.width,h:b.height});})()"
    let rect = script("tell application \"Google Chrome\" to execute active tab of front window javascript \(quoted(js))")
    let state = ["tab": id, "previous": previous, "rect": rect]
    try JSONSerialization.data(withJSONObject: state).write(to: URL(fileURLWithPath: statePath))
    key(44); usleep(1600000)
    print("Opened synthetic source, selected text and summoned annotation mode.")
} else if mode == "draw" {
    let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
    let state = try JSONSerialization.jsonObject(with: data) as! [String: String]
    let rect = try JSONSerialization.jsonObject(with: state["rect"]!.data(using: .utf8)!) as! [String: Double]
    let start = CGPoint(x: rect["x"]! + 2, y: rect["y"]! + 2), end = CGPoint(x: rect["x"]! + rect["w"]! - 2, y: rect["y"]! + rect["h"]! - 2)
    CGWarpMouseCursorPosition(start)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
    for step in 1...16 {
        let p = CGPoint(x: start.x + (end.x-start.x)*Double(step)/16, y: start.y + (end.y-start.y)*Double(step)/16)
        CGWarpMouseCursorPosition(p); CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap); usleep(20000)
    }
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
    print("Drew a rectangle around the synthetic visual.")
} else if mode == "commit" {
    _ = script("tell application \"System Events\" to tell process \"MouseCompanion\"\nrepeat with w in windows\nrepeat with b in (entire contents of w)\ntry\nif role of b is \"AXButton\" and name of b is \"保存选区\" then\nperform action \"AXPress\" of b\nreturn true\nend if\nend try\nend repeat\nend repeat\nend tell")
    usleep(800000)
    print("Saved current context while keeping annotation mode open.")
} else if mode == "ask" {
    text("只做验证：回答选中文字中的盒子名称，以及圈选图片的颜色、形状和数量。如果没收到图片，请明确说只能读文字。")
    usleep(200000); key(36); print("Submitted synthetic context question.")
} else if mode == "review" {
    _ = script("tell application \"System Events\" to tell process \"MouseCompanion\"\nclick menu bar item 1 of menu bar 1\nclick menu item \"查看共享上下文…\" of menu 1 of menu bar item 1 of menu bar 1\nend tell")
} else if mode == "cleanup" {
    let data = try Data(contentsOf: URL(fileURLWithPath: statePath)); let state = try JSONSerialization.jsonObject(with: data) as! [String: String]
    _ = script("tell application \"Google Chrome\"\nclose tab id \(state["tab"]!) of front window\nset active tab index of front window to \(state["previous"]!)\nend tell")
    print("Restored browser tab.")
} else {
    print(script("tell application \"System Events\" to tell process \"MouseCompanion\" to return {name, size, position} of every window"))
    print(script("tell application \"System Events\" to tell process \"MouseCompanion\"\nset output to \"\"\nrepeat with w in windows\nrepeat with t in (entire contents of w)\ntry\nif role of t is \"AXStaticText\" or role of t is \"AXTextArea\" or role of t is \"AXCheckBox\" then set output to output & (value of t as text) & linefeed\nend try\nend repeat\nend repeat\nreturn output\nend tell"))
}

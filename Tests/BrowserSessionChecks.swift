import AppKit

@main
struct BrowserSessionChecks {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 5,
              let url = URL(string: CommandLine.arguments[1]), let x = Double(CommandLine.arguments[2]), let y = Double(CommandLine.arguments[3]),
              let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else { exit(2) }
        let expected = CommandLine.arguments[4]
        let context = BrowserDragContext(bundleID: "com.google.Chrome", processID: chrome.processIdentifier, screenPoint: CGPoint(x: x, y: y))
        var done = false
        var success = false
        var round = 0
        let request = BrowserCaptureRequest()
        var run: (() -> Void)!
        run = { request.start(url: url, context: context) { result in
            round += 1
            let output: [String: Any] = ["matched": result.matched, "titleMatches": result.title == expected, "hasImage": result.image != nil, "hint": result.hint ?? ""]
            print(String(decoding: try! JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
            if let image = result.image, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/mouse-companion-browser-session-preview.png"))
            }
            success = result.matched && result.title == expected && result.image != nil
            if success && round < 2 { run() } else { done = true }
        } }
        run()
        let deadline = Date().addingTimeInterval(20)
        while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        request.cancel()
        run = nil
        if !success { exit(1) }
    }
}

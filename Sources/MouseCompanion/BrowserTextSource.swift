import AppKit

enum BrowserTextSource {
    static func read(context: BrowserDragContext, expectedText: String, completion: @escaping (String?) -> Void) {
        guard BrowserCaptureRequest.supportedBrowsers.contains(context.bundleID), !expectedText.isEmpty else { completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let safari = context.bundleID == "com.apple.Safari"
            let tab = safari ? "current tab of front window" : "active tab of front window"
            let js = "JSON.stringify({url:location.href,selection:(getSelection()?.toString() || '').slice(0,512)})"
            let command = safari ? "do JavaScript \(BrowserCaptureRequest.quoted(js)) in \(tab)" : "execute \(tab) javascript \(BrowserCaptureRequest.quoted(js))"
            let script = "with timeout of 5 seconds\n tell application id \(BrowserCaptureRequest.quoted(context.bundleID))\n return \(command)\n end tell\nend timeout"
            var error: NSDictionary?
            let value = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
            let object = value?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            func normalized(_ text: String) -> String { String(text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(200)) }
            var url: String?
            if error == nil, let selection = object?["selection"] as? String, normalized(selection) == normalized(expectedText) {
                url = object?["url"] as? String
            }
            DispatchQueue.main.async { completion(url) }
        }
    }
}

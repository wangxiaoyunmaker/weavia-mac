import AppKit
import CoreGraphics
import ScreenCaptureKit

struct BrowserDragContext {
    let bundleID: String
    let processID: pid_t
    let screenPoint: CGPoint
    let startedAt = Date()
}

final class BrowserCaptureRequest {
    struct Result {
        var matched = false
        var title: String?
        var image: NSImage?
        var hint: String?
        var sourceURL: String?
        var imageURL: String?
        var rendered = false
        var text: String?
        var textSource: String?
        var textTruncated = false
    }

    static let supportedBrowsers: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.microsoft.edgemac", "com.brave.Browser", "com.apple.Safari"]
    private var cancelled = false

    static func javascript(url: URL, point: CGPoint, body: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["url": url.absoluteString, "x": point.x, "y": point.y])
        return "(() => { const CAPTURE_INPUT = \(String(decoding: data, as: UTF8.self)); return \(body) })();"
    }

    static func samePage(_ a: String, _ b: String) -> Bool {
        BrowserDragPayload.sameURL(a, b)
    }

    func cancel() { cancelled = true }

    func start(url: URL, context: BrowserDragContext, completion: @escaping (Result) -> Void) {
        guard Self.supportedBrowsers.contains(context.bundleID) else { completion(Result()); return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = read(url: url, context: context)
            DispatchQueue.main.async { [self] in
                guard !cancelled else { return }
                if let rect = result.rect, result.result.image == nil {
                    Task { @MainActor [self] in
                        var value = result.result
                        value.image = await Self.captureImage(rect: rect, context: context)
                        value.rendered = value.image != nil
                        guard !self.cancelled else { return }
                        if value.image == nil {
                            if !CGPreflightScreenCaptureAccess() {
                                value.hint = "标题来自当前浏览器。请在系统设置的「隐私与安全性 → 屏幕与系统音频录制」中允许 Mouse Companion，随后点重试以截取来源图片。"
                                _ = CGRequestScreenCaptureAccess()
                            } else {
                                value.hint = "标题来自当前浏览器，但来源图片未能截取。请保持图片在浏览器可视区域，再重试或重新拖入。"
                            }
                        }
                        completion(value)
                    }
                    return
                }
                completion(result.result)
            }
        }
    }

    private struct ReadResult { var result: Result; var rect: CGRect? }

    private func read(url: URL, context: BrowserDragContext) -> ReadResult {
        let safari = context.bundleID == "com.apple.Safari"
        let tab = safari ? "current tab of front window" : "active tab of front window"
        let browser = "application id \(Self.quoted(context.bundleID))"
        let script = "with timeout of 5 seconds\n tell \(browser)\n return {\(safari ? "name" : "title") of \(tab), URL of \(tab)}\n end tell\nend timeout"
        var error: NSDictionary?
        guard let record = NSAppleScript(source: script)?.executeAndReturnError(&error), error == nil,
              let pageURL = record.atIndex(2)?.stringValue else {
            return ReadResult(result: Result(hint: "需要允许 Mouse Companion 读取来源浏览器。请在系统设置的「隐私与安全性 → 自动化」中允许控制该浏览器，然后点重试。"))
        }
        let pageMatches = Self.samePage(pageURL, url.absoluteString)
        let pageTitle = pageMatches ? record.atIndex(1)?.stringValue : nil
        guard let path = Bundle.main.url(forResource: "BrowserCapture", withExtension: "js") ?? Bundle.module.url(forResource: "BrowserCapture", withExtension: "js"), let body = try? String(contentsOf: path, encoding: .utf8) else {
            return ReadResult(result: Result(matched: pageMatches, title: pageTitle))
        }
        let js = Self.javascript(url: url, point: context.screenPoint, body: body)
        let command = safari ? "do JavaScript \(Self.quoted(js)) in \(tab)" : "execute \(tab) javascript \(Self.quoted(js))"
        error = nil
        let data = NSAppleScript(source: "with timeout of 5 seconds\n tell \(browser)\n return \(command)\n end tell\nend timeout")?.executeAndReturnError(&error).stringValue
        guard error == nil, let data = data?.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let message = error?["NSAppleScriptErrorMessage"] as? String ?? ""
            let hint: String
            if message.contains("JavaScript through AppleScript is turned off") || message.contains("JavaScript from Apple Events") {
                hint = "读取页内图片需要在浏览器的「开发者」菜单开启「允许来自 Apple 事件的 JavaScript」，随后点重试。"
            } else if (error?["NSAppleScriptErrorNumber"] as? Int) == -1743 {
                hint = "请在系统设置的「隐私与安全性 → 自动化」中允许 Mouse Companion 控制来源浏览器，随后点重试。"
            } else {
                hint = "来源页面的内容读取未完成。请保持来源标签页打开，随后点重试；也可以重新拖入图片。"
            }
            return ReadResult(result: Result(matched: pageMatches, title: pageTitle, hint: hint))
        }
        guard object["matched"] as? Bool == true else {
            return ReadResult(result: Result(hint: object["frameUnavailable"] as? Bool == true ? "这篇笔记的内嵌详情仍在加载或暂不可访问；请稍后重试。" : nil))
        }
        if object["inFrame"] as? Bool == true {
            guard let contentURL = object["contentURL"] as? String, Self.samePage(contentURL, url.absoluteString) else { return ReadResult(result: Result()) }
        }
        // Reject navigation that occurred while this capture was being prepared.
        guard let returnedURL = object["pageURL"] as? String, Self.samePage(returnedURL, pageURL) else { return ReadResult(result: Result()) }
        let title = (object["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var image: NSImage?
        if let uri = object["imageData"] as? String, uri.hasPrefix("data:image/png;base64,"),
           let data = Data(base64Encoded: String(uri.dropFirst("data:image/png;base64,".count))) { image = NSImage(data: data) }
        var rect: CGRect?
        if let value = object["rect"] as? [String: Double], let x = value["x"], let y = value["y"], let w = value["width"], let h = value["height"], [x,y,w,h].allSatisfy({ $0.isFinite }), w > 0, h > 0 {
            rect = CGRect(x: x, y: y, width: w, height: h)
        }
        let text = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = Result(matched: true, title: title ?? pageTitle, image: image, sourceURL: object["sourceURL"] as? String ?? pageURL, imageURL: object["imageURL"] as? String)
        if let text, !text.isEmpty {
            value.text = String(text.prefix(24000)); value.textSource = object["textSource"] as? String
            value.textTruncated = object["textTruncated"] as? Bool == true || text.count > 24000
        }
        return ReadResult(result: value, rect: rect)
    }

    private static func captureImage(rect: CGRect, context: BrowserDragContext) async -> NSImage? {
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.owningApplication?.processID == context.processID && $0.windowLayer == 0 && $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else { return nil }
        let frame = window.frame
        let crop = frame.intersection(rect)
        guard !crop.isNull, crop.width > 8, crop.height > 8 else { return nil }
        let config = SCStreamConfiguration()
        config.width = Int(frame.width * 2)
        config.height = Int(frame.height * 2)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        let sx = CGFloat(image.width) / frame.width, sy = CGFloat(image.height) / frame.height
        let local = CGRect(x: (crop.minX - frame.minX) * sx, y: (crop.minY - frame.minY) * sy, width: crop.width * sx, height: crop.height * sy)
        guard let thumbnail = image.cropping(to: local) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: crop.width, height: crop.height))
    }

    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}

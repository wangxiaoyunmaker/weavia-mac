import AppKit
import WebKit

@main
final class BrowserDOMChecks: NSObject, WKNavigationDelegate {
    private var web: WKWebView!
    private var finished = false
    private var failures = 0
    private var body = ""

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let check = BrowserDOMChecks()
        check.run()
        if check.failures > 0 || !check.finished { exit(1) }
    }

    private func run() {
        body = try! String(contentsOfFile: "Sources/MouseCompanion/BrowserCapture.js", encoding: .utf8)
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        web.navigationDelegate = self
        let image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5GkAAAAASUVORK5CYII="
        web.loadHTMLString("""
        <title>已登录的信息流页面</title>
        <section class="note-item"><a href="https://fixture.invalid/post/other"><img width="120" height="80" src="\(image)"></a><div class="title">另一张卡片</div></section>
        <section class="note-item"><a href="https://fixture.invalid/post/selected?xsec_token=session"><img width="120" height="80" src="\(image)"></a><div class="title">仅在当前登录页面显示的标题</div></section>
        <section class="note-item"><a href="https://fixture.invalid/watch?v=one">第一个视频</a></section>
        """, baseURL: URL(string: "https://fixture.invalid/feed"))
        let deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        verify("https://fixture.invalid/post/selected?xsec_token=different", expectedTitle: "仅在当前登录页面显示的标题", expectImage: true) {
            self.verify("https://fixture.invalid/post/missing", expectedTitle: nil, expectImage: false) {
                self.verify("https://fixture.invalid/watch?v=two", expectedTitle: nil, expectImage: false) {
                    self.finished = true
                    print("Browser DOM checks: \(self.failures == 0 ? "PASS" : "FAIL")")
                }
            }
        }
    }

    private func verify(_ url: String, expectedTitle: String?, expectImage: Bool, next: @escaping () -> Void) {
        let input = try! JSONSerialization.data(withJSONObject: ["url": url, "x": -1000, "y": -1000])
        let returning = "(() => { const CAPTURE_INPUT = \(String(decoding: input, as: UTF8.self)); return \(self.body) })()"
        web.evaluateJavaScript(returning) { value, error in
                guard error == nil, let value = value as? String, let data = value.data(using: .utf8),
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.failures += 1; print("DOM extraction failed: \(error?.localizedDescription ?? "no result")"); next(); return
                }
                let matched = result["matched"] as? Bool == true
                if matched != (expectedTitle != nil) { self.failures += 1 }
                if let expectedTitle, result["title"] as? String != expectedTitle { self.failures += 1 }
                if expectImage, (result["imageData"] as? String)?.hasPrefix("data:image/png;base64,") != true { self.failures += 1 }
                next()
        }
    }
}

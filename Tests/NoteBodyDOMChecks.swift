import AppKit
import WebKit

@main final class NoteBodyDOMChecks: NSObject, WKNavigationDelegate {
    private var web: WKWebView!
    private var index = 0
    private var done = false
    private let script = try! String(contentsOfFile: "Sources/MouseCompanion/BrowserCapture.js", encoding: .utf8)
    private struct Case {
        var page: String; var target: String; var html: String
        var expected: String?; var source: String?; var partial: Bool
    }
    private let cases: [Case] = [
        Case(page: "https://www.xiaohongshu.com/explore/6ae5696f0000000019002bbd", target: "https://www.xiaohongshu.com/search_result/6ae5696f0000000019002bbd?xsec_token=fixture", html: "<div id='noteContainer'><h1 id='detail-title'>真实路由结构回归</h1><div id='detail-desc'>同一个笔记ID，搜索路径和详情路径。</div></div>", expected: "同一个笔记ID，搜索路径和详情路径。", source: "browser_note_body", partial: false),
        Case(page: "https://www.xiaohongshu.com/explore/6ae5696f0000000019002bbe", target: "https://www.xiaohongshu.com/search_result/6ae5696f0000000019002bbd", html: "<div id='noteContainer'><h1 id='detail-title'>另一篇笔记</h1><div id='detail-desc'>不能误读这篇正文。</div></div>", expected: nil, source: nil, partial: false),
        Case(page: "https://fixture.invalid/note/current", target: "https://fixture.invalid/note/current", html: "<title>笔记</title><div id='noteContainer'><h1 id='detail-title'>三步访谈方法</h1><div id='detail-desc'><p>先试用，再追问。</p><p>保留反例与适用条件。</p><div class='comment-list'>评论不应进入正文</div></div></div><aside>推荐：不要读取我</aside>", expected: "先试用，再追问。\n保留反例与适用条件。", source: "browser_note_body", partial: false),
        Case(page: "https://fixture.invalid/feed", target: "https://fixture.invalid/note/selected", html: "<section class='note-item'><a href='/note/other'>另一个笔记</a><div class='desc'>错误正文</div></section><section class='note-item'><a href='/note/selected'>选中卡片</a><div class='desc'>只是一段摘要</div></section><div id='noteContainer'><div id='detail-desc'>不相关的已打开详情</div></div>", expected: "只是一段摘要", source: "browser_card_excerpt", partial: true),
        Case(page: "https://fixture.invalid/note/cover", target: "https://fixture.invalid/note/cover", html: "<title>只有封面</title><main><h1>标题</h1><img src='cover.png'></main>", expected: nil, source: nil, partial: false),
        Case(page: "https://fixture.invalid/note/summary", target: "https://fixture.invalid/note/summary", html: "<title>摘要</title><meta name='description' content='站点提供的摘要'>", expected: "站点提供的摘要", source: "browser_page_summary", partial: true),
        Case(page: "https://fixture.invalid/note/current", target: "https://fixture.invalid/note/missing", html: "<div id='noteContainer'><h1 id='detail-title'>另一篇笔记</h1><div id='detail-desc'>不要偷读其他笔记</div></div>", expected: nil, source: nil, partial: false),
        Case(page: "https://fixture.invalid/note/long", target: "https://fixture.invalid/note/long", html: "<div id='noteContainer'><h1>长正文</h1><div id='detail-desc'>" + String(repeating: "😀", count: 24005) + "</div></div>", expected: String(repeating: "😀", count: 24000), source: "browser_note_body", partial: true)
    ]
    static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let check = NoteBodyDOMChecks(); check.web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600)); check.web.navigationDelegate = check; check.load()
        let deadline = Date().addingTimeInterval(30)
        while !check.done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        precondition(check.done)
        print("PASS: exact note body, paragraph preservation, scoped feed excerpt, comments/recommendations excluded, missing body, summary and Unicode-safe truncation")
    }
    private func load() { let item = cases[index]; web.loadHTMLString(item.html, baseURL: URL(string: item.page)) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let item = cases[index]
        let input = String(data: try! JSONSerialization.data(withJSONObject: ["url": item.target, "x": -1000, "y": -1000]), encoding: .utf8)!
        web.evaluateJavaScript("(() => { const CAPTURE_INPUT = \(input); return \(script) })()") { value, error in
            precondition(error == nil, "DOM script error: \(String(describing: error))")
            let object = try! JSONSerialization.jsonObject(with: Data((value as! String).utf8)) as! [String: Any]
            let actual = object["text"] as? String
            precondition(actual == item.expected, "Body case \(self.index) failed: \(String(describing: actual?.prefix(100)))")
            precondition(object["textSource"] as? String == item.source)
            precondition((object["textTruncated"] as? Bool ?? false) == item.partial)
            self.index += 1
            if self.index == self.cases.count { self.done = true } else { self.load() }
        }
    }
}

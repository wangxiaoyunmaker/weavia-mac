import AppKit
import WebKit

final class Harness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var web: WKWebView!
    var ready = false
    var saved = false
    var error: String?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "ready" { ready = true }
        if action == "saveCanvas" { saved = true }
        let id = body["requestId"] as? String ?? ""
        let encoded = String(data: try! JSONSerialization.data(withJSONObject: [id]), encoding: .utf8)!
        web.evaluateJavaScript("mouseCompanionMac.ack(\(encoded)[0],{ok:true});", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.error = error.localizedDescription }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
    }
}
@main struct MacWorkspaceWebKitChecks {
    static func main() throws {
        func check(_ value: Bool) { precondition(value) }
        let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-workspace-webkit-" + UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = NSApplication.shared
        let delegate = Harness(), config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(delegate, name: "mouseCompanion")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820), configuration: config)
        delegate.web = web; web.navigationDelegate = delegate
        let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web // Never ordered, activated, or made key.
        func spin(_ condition: () -> Bool, timeout: TimeInterval = 40) throws {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            if !condition() { throw NSError(domain: "WebKitChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: delegate.error ?? "Timed out"]) }
        }
        func evaluate(_ script: String) throws -> Any? {
            var done = false, value: Any?, failure: Error?
            web.evaluateJavaScript(script) { value = $0; failure = $1; done = true }
            try spin({ done }); if let failure { throw failure }; return value
        }
        var url = URLComponents(url: root.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false)!
        url.fragment = "cuppa"
        url.queryItems = [URLQueryItem(name: "project", value: "synthetic-test")]
        web.loadFileURL(url.url!, allowingReadAccessTo: root)
        try spin({ delegate.ready || delegate.error != nil })
        if let error = delegate.error { throw NSError(domain: "WebKitChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: error]) }
        check(try evaluate("Boolean(cuppaReady && mouseCompanionMac && document.body.style.visibility !== 'hidden')") as? Bool == true)
        print("PASS: actual file:// canvas modules boot in offscreen nonpersistent WebKit")
        let injected = try evaluate("""
        (()=>{localStorage.setItem('isolated-probe','ok'); if(localStorage.getItem('isolated-probe')!=='ok')throw Error('localStorage failed');return mouseCompanionMac.receiveSnapshot({version:1,revision:1,projectId:'synthetic-test',projects:[{id:'synthetic-test',name:'Synthetic test'}],mode:'focus',materials:[{id:'fixture-card',title:'Synthetic material',text:'Fixture only',saved:true,kind:'文字卡片'}]});})()
        """) as? [String: Any]
        precondition(injected?["ok"] as? Bool == true)
        try spin({ delegate.saved })
        check(try evaluate("Boolean(state.cards.some(c=>c.nativeMaterialId==='fixture-card') && document.body.innerText.includes('Synthetic material'))") as? Bool == true)
        print("PASS: native snapshot merge, rendered synthetic card, file localStorage and save acknowledgement")
        var snapshotDone = false
        var snapshotError: Error?
        web.takeSnapshot(with: nil) { image, error in
            defer { snapshotDone = true }; snapshotError = error
            if let image, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]), CommandLine.arguments.count > 2 {
                do { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2])) } catch { snapshotError = error }
            }
        }
        try spin({ snapshotDone }); if let snapshotError { print("SNAPSHOT_LIMITATION: \(snapshotError.localizedDescription)") }
        _ = try evaluate("""
        window.memoryProbe={done:false}; (async()=>{try{const legacy=createDurableProjectMemoryStore('synthetic-memory');await legacy.read();legacy.dispose();const s=mouseCompanionMac.createMemoryStore('synthetic-test');const result=await s.read();const saved=await s.put(result.token,{kind:'goal',text:'Synthetic goal'});if(!saved.document.entries.some(e=>e.text==='Synthetic goal'))throw Error('Native memory save failed');window.memoryProbe={done:true,ok:true,entries:saved.document.entries.length};s.dispose();}catch(e){window.memoryProbe={done:true,ok:false,error:e.message};}})(); true
        """)
        let deadline = Date().addingTimeInterval(20)
        var probe: [String: Any] = [:]
        repeat { RunLoop.current.run(until: Date().addingTimeInterval(0.1)); probe = (try evaluate("window.memoryProbe") as? [String: Any]) ?? [:] } while probe["done"] as? Bool != true && Date() < deadline
        print("PROJECT_MEMORY_INDEXEDDB: \(probe)")
        precondition(probe["ok"] as? Bool == true, "File-origin IndexedDB project-memory unavailable")
        precondition(!window.isVisible, "Offscreen window became visible")
        print("PASS: file-origin IndexedDB project-memory and no visible window")
    }
}

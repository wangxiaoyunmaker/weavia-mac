import AppKit
import WebKit

/// Synthetic, offscreen integration test of the production WKWebView bridge.
@main struct WeaviaAnswerPresentationChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        setenv("MOUSE_COMPANION_PROJECTS_DIR", root.appendingPathComponent("Projects").path, 1)
        _ = NSApplication.shared
        let context = CompanionContext()
        context.selectProject("Answer presentation fixture " + UUID().uuidString)
        let controller = MacWorkspaceCanvas(context: context)
        var requests: [String] = []
        controller.onAgent = { _, _, id in requests.append(id) }
        func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        func evaluate(_ script: String) throws -> Any? {
            var done = false, value: Any?, failure: Error?
            controller.webView.evaluateJavaScript(script) { value = $0; failure = $1; done = true }
            let deadline = Date().addingTimeInterval(10)
            while !done && Date() < deadline { spin(0.05) }
            if let failure { throw failure }
            guard done else { throw NSError(domain: "AnswerPresentationChecks", code: 1) }
            return value
        }
        func check(_ script: String, _ message: String) throws {
            guard try evaluate(script) as? Bool == true else { print("FAIL: \(message)"); exit(1) }
            precondition(!controller.window.isVisible, "Tests must remain offscreen")
            print("PASS: \(message)")
        }
        func start() throws -> String {
            let count = requests.count
            _ = try evaluate("mouseCompanionMac.openAgent('Synthetic prompt: no network', []); true")
            let deadline = Date().addingTimeInterval(5)
            while requests.count == count && Date() < deadline { spin(0.05) }
            guard requests.count == count + 1 else { throw NSError(domain: "NoNativeRequest", code: 2) }
            return requests.last!
        }
        func send(_ id: String, _ status: String, project: String? = nil) throws {
            controller.receiveAgentResult(requestID: id, status: status, text: "# Synthetic answer\n**Markdown** only\n<script>window.injected = true</script>", project: project ?? context.project)
            spin(0.15)
        }
        spin(12)
        _ = try evaluate("document.getElementById('open-cuppa').click(); true")
        spin(1)
        _ = try evaluate("""
        window.presentationCalls = {panel:0,modal:0,notify:0};
        const realPanel=panel,realModal=modal,realNotify=notify;
        panel=function(...args){presentationCalls.panel++;return realPanel(...args);};
        modal=function(...args){presentationCalls.modal++;return realModal(...args);};
        notify=function(...args){presentationCalls.notify++;return realNotify(...args);};
        window.presentationSnapshot=()=>JSON.stringify({panel:document.getElementById('result-panel').outerHTML,dialogs:[...document.querySelectorAll('dialog')].map(d=>d.outerHTML),toast:document.getElementById('toast').outerHTML,calls:presentationCalls});
        window.capturePresentation=()=>{window.beforePresentation=presentationSnapshot();};
        window.presentationUnchanged=()=>presentationSnapshot()===beforePresentation&&!window.injected&&!document.getElementById('mac-agent-stop');
        true
        """)
        for terminal in ["completed", "success", "failed", "error", "cancelled"] {
            let id = try start()
            _ = try evaluate("capturePresentation(); true")
            try send(id, "streaming")
            try send(id, "streaming")
            try check("presentationUnchanged()", "\(terminal): repeated streaming never opens a web answer, dialog, or toast")
            try send(id, terminal)
            let encodedID = String(data: try JSONSerialization.data(withJSONObject: [id]), encoding: .utf8)!
            try check("mouseCompanionMac.receiveAgentResult({requestId:(\(encodedID))[0],status:'streaming',text:'late'})===false", "\(terminal): completed request ID is retired")
            try check("presentationUnchanged()", "\(terminal): terminal callback never adds a web answer or notification")
            try send(id, "streaming")
            try send(id, "completed")
            try check("presentationUnchanged()", "\(terminal): late callbacks cannot reopen a dismissed answer")
        }
        let closedID = try start()
        _ = try evaluate("panel('User panel','<p>Fixture panel</p>');document.getElementById('close-results').click();modal('User dialog','<p>Fixture dialog</p>');document.getElementById('dialog').close();capturePresentation();true")
        try send(closedID, "streaming")
        try send(closedID, "completed")
        try check("presentationUnchanged()&&!document.getElementById('dialog').open&&document.getElementById('result-panel').hidden", "closed user panel and dialog stay closed after reply callbacks")
        let panelID = try start()
        _ = try evaluate("panel('User search results','<input id=fixture-input value=untouched><p>Keep these results</p>');capturePresentation();true")
        try send(panelID, "streaming")
        try send(panelID, "failed")
        try check("presentationUnchanged()&&!document.getElementById('result-panel').hidden&&document.getElementById('fixture-input').value==='untouched'", "user-opened panel remains byte-for-byte unchanged during streaming and failure")
        let dialogID = try start()
        _ = try evaluate("modal('User editing dialog','<input id=fixture-dialog-input value=preserve>');capturePresentation();true")
        try send(dialogID, "streaming")
        try send(dialogID, "completed")
        try check("presentationUnchanged()&&document.getElementById('dialog').open&&document.getElementById('fixture-dialog-input').value==='preserve'", "user-opened modal remains unchanged during reply and completion")
        _ = try evaluate("document.getElementById('dialog').close();true")
        let oldID = try start()
        let newID = try start()
        _ = try evaluate("capturePresentation();true")
        for status in ["streaming", "completed", "failed", "cancelled"] { try send(oldID, status) }
        try check("presentationUnchanged()", "older request callbacks do not change the current user panel")
        try send(newID, "streaming", project: "Different synthetic project")
        try send(newID, "completed", project: "Different synthetic project")
        try check("presentationUnchanged()", "native controller ignores out-of-project callbacks")
        // Direct bridge return values verify stale IDs and mismatched projects are rejected,
        // rather than merely invisible. The callbacks above exercise the actual native method.
        let json = String(data: try JSONSerialization.data(withJSONObject: ["old":oldID,"current":newID,"project":context.project]), encoding: .utf8)!
        _ = try evaluate("window.fixtureIDs=\(json);true")
        try check("mouseCompanionMac.receiveAgentResult({requestId:fixtureIDs.old,projectId:fixtureIDs.project,status:'streaming',text:'old'})===false", "bridge rejects superseded request ID")
        try check("mouseCompanionMac.receiveAgentResult({requestId:fixtureIDs.current,projectId:'Other project',status:'completed',text:'other'})===false", "bridge rejects out-of-project result without ending current request")
        try check("mouseCompanionMac.receiveAgentResult({requestId:fixtureIDs.current,projectId:fixtureIDs.project,status:'streaming',text:'current'})===true", "current request remains valid after ignored callbacks")
        try send(newID, "cancelled")
        try check("mouseCompanionMac.receiveAgentResult({requestId:fixtureIDs.current,projectId:fixtureIDs.project,status:'streaming',text:'late'})===false", "cancelled request is retired and rejects late streaming")
        try check("presentationUnchanged()", "all stale and cancelled callbacks preserve the user panel")
        print("PASS: actual offscreen MacWorkspaceCanvas answer presentation checks; synthetic data only, no model/network calls, credentials, screen capture, or visible windows")
    }
}

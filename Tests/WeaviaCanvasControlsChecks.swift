import AppKit
import WebKit

@main struct WeaviaCanvasControlsChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        setenv("MOUSE_COMPANION_PROJECTS_DIR", root.appendingPathComponent("Projects").path, 1)
        _ = NSApplication.shared
        let context = CompanionContext()
        context.selectProject("Controls fixture " + UUID().uuidString)
        for i in 0..<3 {
            context.upsert(CompanionMaterial(id: String(format: "00000000-0000-4000-8000-%012d", i), project: context.project, title: "Synthetic material \(i)", text: "Fixture only", note: "", area: "Fixture", image: nil, saved: true))
        }
        let controller = MacWorkspaceCanvas(context: context)
        func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        func evaluate(_ script: String) throws -> Any? {
            var done = false, value: Any?, failure: Error?
            controller.webView.evaluateJavaScript(script) { value = $0; failure = $1; done = true }
            let deadline = Date().addingTimeInterval(10)
            while !done && Date() < deadline { spin(0.05) }
            if let failure { throw failure }
            if !done { throw NSError(domain: "ControlsChecks", code: 1) }
            return value
        }
        func check(_ script: String, _ message: String) throws {
            guard try evaluate(script) as? Bool == true else { print("FAIL: \(message)"); exit(1) }
            print("PASS: \(message)")
            precondition(!controller.window.isVisible, "Must remain offscreen")
        }
        spin(12)
        _ = try evaluate("document.getElementById('open-cuppa').click(); true")
        spin(2)
        try check("state.cards.filter(c=>c.nativeMaterialId).length===3", "native synthetic materials loaded")
        _ = try evaluate("""
        window.controlsVisible = id => {
          const el=document.getElementById(id); if(!el)return false;
          const r=el.getBoundingClientRect(); if(r.width<=0||r.height<=0||r.left<0||r.top<0||r.right>innerWidth+1||r.bottom>innerHeight+1)return false;
          for(let p=el;p;p=p.parentElement){const s=getComputedStyle(p);if(p.hidden||s.display==='none'||s.visibility==='hidden'||Number(s.opacity)===0)return false;}
          return true;
        };
        window.controlIDs=['select-tool','hand-tool','canvas-rectangle-tool','canvas-lasso-tool','canvas-pen-tool','canvas-undo-tool','add-tool'];
        window.controlsInvariant=()=>{document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish();});return !['canvas-primary-actions','canvas-prompt-entry','canvas-search-toggle','canvas-mark-tools-toggle'].some(id=>document.getElementById(id)) && controlsVisible('search-shell') && controlIDs.every(id=>controlsVisible(id)) && controlIDs.every(id=>{const e=document.getElementById(id);return !!e.querySelector('svg,img')&&!!e.getAttribute('aria-label')&&!e.textContent.trim();});};
        true
        """)
        for size in [NSSize(width:1280,height:820),NSSize(width:900,height:600)] {
            controller.window.setContentSize(size)
            controller.webView.frame = NSRect(origin:.zero,size:size)
            spin(0.5)
            // Offscreen WKWebView pauses entry animations; verify the settled layout.
            _ = try evaluate("controlsInvariant()")
            let dimensions = try evaluate("JSON.stringify({width:innerWidth,height:innerHeight,controls:controlIDs.map(id=>({id,visible:controlsVisible(id),rect:document.getElementById(id)?.getBoundingClientRect().toJSON()})),search:document.getElementById('search-shell').getBoundingClientRect().toJSON()})")
            print("LAYOUT: \(dimensions ?? "nil")")
            try check("controlsInvariant()", "original search and persistent accessible icon toolbar at \(size)")
            for mode in ["rectangle","lasso","pen"] {
                _ = try evaluate("document.getElementById('canvas-\(mode)-tool').click(); true")
                try check("tool==='\(mode)' && document.getElementById('canvas-\(mode)-tool').getAttribute('aria-pressed')==='true' && controlsInvariant()", "click selects \(mode) without collapsing icons")
            }
            for mode in ["select","hand"] {
                _ = try evaluate("document.getElementById('\(mode)-tool').click(); true")
                try check("tool==='\(mode)' && controlsInvariant()", "\(mode) remains functional and icons persist")
            }
            _ = try evaluate("document.getElementById('add-tool').click(); true")
            try check("!document.getElementById('more-menu').hidden && controlsInvariant()", "add menu remains functional")
            _ = try evaluate("showCreationMenu(null); cuppaContextCapture.beginInspiration(); chooseTool('pen'); cuppaContextCapture.endInspiration(); true")
            try check("tool==='select' && controlsInvariant()", "endInspiration retains search and all icons")
            for mode in ["focus","cocreate"] {
                _ = try evaluate("cuppaWorkModeV1.sync({available:true,mode:'\(mode)'}); true")
                try check("controlsInvariant()", "\(mode) work mode retains search and all icons")
            }
            _ = try evaluate("location.hash=''; true")
            spin(0.5)
            _ = try evaluate("location.hash='#cuppa'; true")
            spin(0.5)
            try check("!document.getElementById('workspace').hidden && controlsInvariant()", "returning from project home retains search and all icons")
            _ = try evaluate("window.cardsBeforeUndo=JSON.stringify(state.cards);state.canvasInk={version:1,strokes:[{id:'fixture-ink',points:[[400,400],[450,450]]}]};cuppaCanvasTools.render();document.getElementById('canvas-undo-tool').click();true")
            try check("state.canvasInk.strokes.length===0 && JSON.stringify(state.cards)===cardsBeforeUndo && controlsInvariant()", "enabled undo removes only ink and preserves every material")
        }
        print("PASS: restored controls verified in actual offscreen MacWorkspaceCanvas WKWebView; no real data, API, keys, screenshots, or visible windows used")
    }
}

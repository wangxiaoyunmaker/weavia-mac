import AppKit
import WebKit

@main struct WeaviaCanvasHistoryUIChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        setenv("MOUSE_COMPANION_PROJECTS_DIR", root.appendingPathComponent("Projects").path, 1)
        _ = NSApplication.shared
        let context = CompanionContext()
        context.selectProject("History fixture " + UUID().uuidString)
        for i in 0..<3 { context.upsert(CompanionMaterial(id: String(format: "00000000-0000-4000-8000-%012d", i), project: context.project, title: "Synthetic material \(i)", text: "Fixture only", note: "", area: "Fixture", image: nil, saved: true)) }
        let controller = MacWorkspaceCanvas(context: context, websiteDataStore: .nonPersistent())
        func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        func js(_ script: String) throws -> Any? {
            var done=false, value: Any?, failure: Error?
            controller.webView.evaluateJavaScript(script) { value=$0;failure=$1;done=true }
            let deadline=Date().addingTimeInterval(15)
            while !done && Date()<deadline { spin(0.05) }
            if let failure { throw failure };if !done { throw NSError(domain:"HistoryJS",code:1) };return value
        }
        func check(_ script: String,_ name: String) throws { guard try js(script) as? Bool == true else { print("FAIL: \(name)");exit(1) };precondition(!controller.window.isVisible);print("PASS: \(name)") }
        func run(_ redo: Bool = false) throws { _ = try js("window.done=false;cuppaCanvasHistory.run(\(redo ? "true":"false")).then(ok=>{window.result=ok;window.done=true});true");let deadline=Date().addingTimeInterval(15);while Date()<deadline { if try js("window.done") as? Bool == true { break };spin(0.1) };try check("window.done&&window.result","history transaction acknowledged");spin(0.2) }
        spin(12);_ = try js("document.getElementById('open-cuppa').click();true");spin(1);_ = try js("document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish()});true")
        try check("state.cards.length===3&&!!cuppaCanvasHistory&&!cuppaCanvasHistory.status().canUndo","startup is not a user edit")
        for size in [NSSize(width:1280,height:820),NSSize(width:900,height:600)] {
            controller.window.setContentSize(size);controller.webView.frame=NSRect(origin:.zero,size:size);spin(0.2)
            try check("['canvas-history-undo','canvas-history-redo'].every(id=>{const e=document.getElementById(id),r=e.getBoundingClientRect();return r.width>30&&r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight&&e.getAttribute('aria-label')&&e.textContent.trim()&&getComputedStyle(document.getElementById('workspace')).visibility!=='hidden'&&!document.getElementById('workspace').hidden})","visible named undo/redo at \(size)")
        }
        _ = try js("window.base=JSON.stringify(WeaviaCanvasHistory.content(state));window.newId=addCard('claim','New idea','Synthetic idea',{x:800,y:700}).id;document.activeElement?.blur();true");spin(0.6)
        try check("cuppaCanvasHistory.status().canUndo&&state.cards.length===4","add card recorded")
        try run();try check("JSON.stringify(WeaviaCanvasHistory.content(state))===base","add undo restores exact original canvas")
        try run(true);try check("state.cards.some(c=>c.id===newId)","redo preserves original card ID")
        _ = try js("cuppaCanvasHistory.reset(state);window.oldX=state.cards[0].x;state.cards[0].x+=75;save();true");spin(0.5)
        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command],timestamp:0,windowNumber:controller.window.windowNumber,context:nil,characters:"z",charactersIgnoringModifiers:"z",isARepeat:false,keyCode:6)!
        precondition(controller.window.performKeyEquivalent(with:event));spin(1)
        try check("state.cards[0].x===oldX&&cuppaCanvasHistory.status().canRedo","native Command-Z routes canvas undo")
        let redoEvent=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.shift],timestamp:0,windowNumber:controller.window.windowNumber,context:nil,characters:"Z",charactersIgnoringModifiers:"z",isARepeat:false,keyCode:6)!
        precondition(controller.window.performKeyEquivalent(with:redoEvent));spin(1)
        try check("state.cards[0].x===oldX+75","native Command-Shift-Z routes redo")
        _ = try js("window.a=state.cards[0].id;window.b=state.cards[1].id;state.connections=[{id:'fixture-edge',from:a,to:b}];state.regions=[{id:'fixture-region',title:'Group',x:100,y:100,width:900,height:600,members:[a,b]}];save();renderRegions();cuppaCanvasHistory.reset(state);window.beforeDelete=JSON.stringify(WeaviaCanvasHistory.content(state));selected=a;deleteSelectedCards();true");spin(0.5)
        try run();try check("JSON.stringify(WeaviaCanvasHistory.content(state))===beforeDelete","deleted card, connection, group membership restored together")
        _ = try js("state.macProjectMemory={version:1,note:'separate-memory'};state.drafts.personal.text='keep search';save();true");spin(0.5)
        try run(true);try check("state.macProjectMemory.note==='separate-memory'&&state.drafts.personal.text==='keep search'&&state.macNativeMaterialIds.length===3","redo preserves project memory search draft and native import receipts")
        try run();
        _ = try js("window.done=false;relationCommit(null,{id:'example-line',from:a,to:newId,relation:{version:1,source:'assistant',kind:'complementary',customLabel:'',evidence:'Synthetic reference only',status:'pending',history:[{author:'assistant',action:'suggested'}]}}).then(()=>window.done=true);true");spin(1)
        try check("window.done&&cuppaCanvasHistory.status().undoLabel==='修改连线'&&CardRelations.view(state.connections.find(e=>e.id==='example-line')).statusLabel==='助手示例 · 待确认'","native relation commit recorded with explicit provenance")
        try run();try check("!state.connections.some(e=>e.id==='example-line')","relationship undo uses same native transaction")
        try run(true);_ = try js("drawGraph();true")
        try check("[...document.querySelectorAll('.relation-edge text')].some(el=>el.textContent==='互补 · 助手示例 · 待确认')","example relationship label is visible in SVG")
        try check("document.getElementById('canvas-history-status').getBoundingClientRect().width<=1&&document.getElementById('canvas-history').getBoundingClientRect().width<240","live announcement does not expand history toolbar")
        if CommandLine.arguments.count > 2 {
            _ = try js("setZoom(.5);pan={x:160,y:100};updateView();document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish()});true");spin(0.4)
            var imageDone=false
            controller.webView.takeSnapshot(with:nil) { image, error in
                if let data=image?.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]) { try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[2])) }
                imageDone=true
            }
            let deadline=Date().addingTimeInterval(10);while !imageDone && Date()<deadline { spin(0.05) }
        }

        _ = try js("window.oldTags=JSON.stringify(state.cards[0].tags);state.cards[0].tags.push('Synthetic tag');save();true");spin(0.5);try run();try check("JSON.stringify(state.cards[0].tags)===oldTags","tags restored")
        _ = try js("state.canvasInk={version:1,strokes:[{id:'fixture-stroke',points:[[1,1],[2,2]]}]};save();true");spin(0.5);try run();try check("!state.canvasInk||state.canvasInk.strokes.length===0","canvas ink restored by general history")
        _ = try js("document.getElementById('query').focus();window.editingBefore=JSON.stringify(state.cards);true")
        try check("cuppaCanvasHistory.keyCommand(false)===false&&JSON.stringify(state.cards)===editingBefore","editing receives native text undo instead of canvas history")
        _ = try js("document.activeElement.blur();state.cards[0].title='External sync';cuppaCanvasHistory.external(state);true")
        try check("!cuppaCanvasHistory.status().canUndo&&!cuppaCanvasHistory.status().canRedo","external changes invalidate unsafe history")
        let disk=try MacCanvasSnapshotStore().load(context.project)
        precondition(disk != nil)
        print("PASS: offline history UI, native shortcuts, acknowledged persistence and boundaries; no visible window or real user data")
    }
}

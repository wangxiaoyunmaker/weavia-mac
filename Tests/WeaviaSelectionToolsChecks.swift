import AppKit
import WebKit

@main struct WeaviaSelectionToolsChecks {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  setenv("MOUSE_COMPANION_PROJECTS_DIR",root.appendingPathComponent("Projects").path,1)
  setbuf(stdout,nil)
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let context=CompanionContext();context.selectProject("Selection fixture "+UUID().uuidString)
  let controller=MacWorkspaceCanvas(context:context)
  func spin(_ seconds:Double){RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
  func evaluate(_ script:String)throws->Any?{
   var done=false,value:Any?,failure:Error?
   controller.webView.evaluateJavaScript(script){value=$0;failure=$1;done=true}
   let end=Date().addingTimeInterval(10);while !done && Date()<end{spin(0.05)}
   if let failure{throw failure};precondition(done);return value
  }
  func check(_ script:String,_ label:String)throws{
   guard try evaluate(script) as? Bool == true else{print("FAIL: "+label);exit(1)}
   precondition(!controller.window.isVisible);print("PASS: "+label)
  }
  func completions()->[[String:Any]]{controller.fixtureMessages.filter{$0["action"] as? String == "selectionCompleted"}}
  func gesture(_ kind:String,_ ending:String="finish")throws{
   _ = try evaluate("runSelectionGesture('\(kind)','\(ending)');true");spin(0.4)
  }
  spin(8);controller.setMode(true);spin(0.5)
  _ = try evaluate("location.hash='#cuppa';true");spin(0.5)
  _ = try evaluate("""
   // Simulate an active tab while keeping every OS window hidden.
   Object.defineProperty(document,'hidden',{get:()=>false,configurable:true});
   document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish()});
   state.cards=[{id:'selection-a',type:'source',title:'Synthetic A',text:'A reference',x:430,y:200,tags:[]},{id:'selection-b',type:'source',title:'Synthetic B',text:'B reference',x:720,y:200,tags:[]}];
   zoom=1;pan={x:0,y:0};renderCards();updateView();
   document.querySelectorAll('.card').forEach(e=>{e.style.width='200px';e.style.height='170px'});
   // Synthetic PointerEvents do not own OS pointer capture. Only the fixture's
   // capture methods are inert; all production event handlers/order remain real.
   const w=document.getElementById('workspace');w.setPointerCapture=()=>{};w.hasPointerCapture=()=>false;
   window.runSelectionGesture=(kind,ending)=>{
    chooseTool(kind);document.activeElement?.blur();
    const rs=[...document.querySelectorAll('.card')].map(e=>e.getBoundingClientRect());
    const l=Math.min(...rs.map(r=>r.left))-12,t=Math.min(...rs.map(r=>r.top))-12,r=Math.max(...rs.map(r=>r.right))+12,b=Math.max(...rs.map(r=>r.bottom))+12;
    let points=ending==='empty'?[[1100,560],[1200,660]]:kind==='lasso'?[[l,t],[r,t],[r,b],[l,b],[l,t]]:[[l,t],[r,b]];
    const send=(type,p)=>w.dispatchEvent(new PointerEvent(type,{bubbles:true,composed:true,pointerId:47,pointerType:'mouse',isPrimary:true,button:0,buttons:type==='pointerup'?0:1,clientX:p[0],clientY:p[1]}));
    send('pointerdown',points[0]);for(const p of points.slice(1))send('pointermove',p);
    send(ending==='cancel'?'pointercancel':'pointerup',points.at(-1));
   };true
  """)
  for kind in ["rectangle","lasso","select"]{
   let before=completions().count;try gesture(kind)
   guard completions().count==before+1 else{print("DEBUG: \(String(describing:try evaluate("JSON.stringify({tool,hidden:document.hidden,selected,ids:[...marqueeIds],ready:cuppaReady,dialog:!!document.querySelector(\"dialog[open]\"),active:document.activeElement?.outerHTML.slice(0,120),status:document.getElementById(\"canvas-tool-status\").textContent,rects:[...document.querySelectorAll(\".card\")].map(e=>e.getBoundingClientRect().toJSON())})")))");print("MESSAGES: \(controller.fixtureMessages.map{$0["action"] as? String ?? ""})");print("FAIL: \(kind) reached native selectionCompleted exactly once; actual \(completions().count-before)");exit(1)}
   let last=completions().last!, cards=last["cards"] as! [[String:Any]]
   precondition(Set(cards.compactMap{$0["id"] as? String})==Set(["selection-a","selection-b"]))
   let bounds=last["bounds"] as! [String:Any];precondition((bounds["width"] as! Double)>0)
   print("PASS: real \(kind) handlers reached native bridge once with both synthetic cards")
   try check("document.getElementById('canvas-context-panel').hidden && document.getElementById('canvas-context-toggle').hidden","\(kind) no obsolete preview panel")
   let session=last["selectionSession"] as! String
   _ = try evaluate("mouseCompanionMac.alignSelection({projectId:new URLSearchParams(location.search).get('project'),selectionSession:'\(session)',visible:true,x:950,y:400});true")
   spin(0.4)
   try check("!document.getElementById('selection-actions').hidden && document.getElementById('selection-count').textContent==='已选 2 张卡片'","\(kind) shared anchored action menu survives polling")
  }
  let beforeCancel=completions().count;try gesture("rectangle","cancel")
  precondition(completions().count==beforeCancel)
  try check("document.getElementById('selection-actions').hidden","cancel does not reopen obsolete actions")
  let beforeEmpty=completions().count;try gesture("rectangle","empty");precondition(completions().count==beforeEmpty)
  print("PASS: empty selection has no native completion")
  controller.setMode(false);spin(0.4)
  let beforeFocus=completions().count;try gesture("lasso");precondition(completions().count==beforeFocus)
  try check("!document.getElementById('canvas-context-panel').hidden","Focus retains manual preview and does not summon companion")
  controller.setMode(true);spin(0.4)
  let beforePen=completions().count;try gesture("pen");precondition(completions().count==beforePen)
  try check("state.canvasInk.strokes.length===1","pen stays local ink without selection completion")
  precondition(controller.fixtureMessages.filter{$0["action"] as? String == "openAgent"}.isEmpty)
  print("PASS: no model request or credential access; production WKWebView modules and native receipt tested with isolated synthetic data, all windows hidden")
 }
}

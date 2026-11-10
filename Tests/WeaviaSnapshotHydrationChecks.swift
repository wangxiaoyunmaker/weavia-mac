import AppKit
import WebKit

@main struct WeaviaSnapshotHydrationChecks {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  setenv("MOUSE_COMPANION_PROJECTS_DIR",root.appendingPathComponent("Projects").path,1)
  setbuf(stdout,nil);_ = NSApplication.shared
  let context=CompanionContext();context.selectProject("Snapshot hydration fixture " + UUID().uuidString)
  let project=context.project,store=MacCanvasSnapshotStore()
  let cards:[[String:Any]]=(0..<6).map { i in ["id":"fixture-\(i)","type":"source","title":"Synthetic card \(i)","text":"Synthetic fixture only","x":350+i*300,"y":180,"time":"10:00","tags":[]] }
  let regions:[[String:Any]]=(0..<6).map { i in ["id":"region-\(i)","title":"合成区域 \(i)","x":330+i*300,"y":130,"width":290,"height":350,"members":["fixture-\(i)"]] }
  var connections:[[String:Any]]=[]
  for from in 0..<6 {for to in (from+1)..<6 {connections.append(["id":"edge-\(from)-\(to)","from":"fixture-\(from)","to":"fixture-\(to)","fromSide":"right","toSide":"left"])}}
  let drafts:[String:Any]=["personal":["text":"preserved draft","sources":[],"refs":[]],"agent":["text":"","sources":[],"refs":[]]]
  let snapshot:[String:Any]=["cards":cards,"regions":regions,"connections":connections,"drafts":drafts,"mode":"personal","resourceSemanticVersion":1,"aiExcerptExamplesAdded":true]
  try store.save(snapshot,project:project)
  let controller=MacWorkspaceCanvas(context:context)
  func spin(_ seconds:Double){RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
  func evaluate(_ script:String)throws->Any?{
   var done=false,value:Any?,failure:Error?
   controller.webView.evaluateJavaScript(script){value=$0;failure=$1;done=true}
   let deadline=Date().addingTimeInterval(10);while !done&&Date()<deadline{spin(0.05)}
   if let failure{throw failure};precondition(done);return value
  }
  func check(_ script:String,_ label:String)throws{
   guard try evaluate(script) as? Bool == true else {print("FAIL: \(label)");exit(1)}
   precondition(!controller.window.isVisible);print("PASS: \(label)")
  }
  spin(12)
  try check("state.cards.length===6 && state.regions.length===6 && state.connections.length===15", "native snapshot loaded from isolated disk on the first cold start")
  try check("document.querySelectorAll('#region-layer .canvas-region').length===6 && [...document.querySelectorAll('#region-layer input')].every((e,i)=>e.value==='合成区域 '+i)", "first asynchronous hydration renders all six region titles without a reopen")
  try check("fixtureFrameRequests>0 && document.getElementById('relation-count').textContent==='15 条 · 手动标注' && document.querySelectorAll('#connection-layer [data-edge]').length===15", "all 15 relationships and count render even when animation frames are paused")
  try check("state.drafts.personal.text==='preserved draft' && state.connections.every(e=>!e.relation)", "draft and ordinary unannotated edges are preserved")
  _ = try evaluate("location.hash='#cuppa';document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish()});window.regionInput=document.querySelector('#region-layer input');regionInput.value='Uncommitted region title';window.regionSnapshot=JSON.stringify(state.regions);window.edgeSnapshot=JSON.stringify(state.connections);true")
  let encodedProject=String(data:try JSONSerialization.data(withJSONObject:[project]),encoding:.utf8)!
  try check("mouseCompanionMac.receiveSnapshot({version:1,projectId:(\(encodedProject))[0],materials:[{id:'new-fixture',saved:true,title:'New synthetic card',text:'Fixture'}],mode:'focus'}).ok===true", "subsequent material sync succeeds")
  try check("document.querySelector('#region-layer input')===regionInput && regionInput.value==='Uncommitted region title' && JSON.stringify(state.regions)===regionSnapshot && JSON.stringify(state.connections)===edgeSnapshot && document.getElementById('relation-count').textContent==='15 条 · 手动标注'", "later sync preserves the active region editor, unsaved text, and all graph data")
  spin(1)
  guard let persisted=try store.load(project),let savedRegions=persisted["regions"] as? [[String:Any]],let savedEdges=persisted["connections"] as? [[String:Any]],savedRegions.count==6,savedEdges.count==15,savedRegions[0]["title"] as? String=="合成区域 0" else {print("FAIL: graph disk persistence changed");exit(1)}
  print("PASS: native saved snapshot retains six regions and 15 ordinary connections")
  let emptyProject="Legacy empty graph fixture "+UUID().uuidString
  try store.save(["cards":[],"drafts":drafts,"mode":"personal","resourceSemanticVersion":1,"aiExcerptExamplesAdded":true],project:emptyProject)
  context.selectProject(emptyProject);spin(8)
  try check("Array.isArray(state.regions)&&state.regions.length===0&&Array.isArray(state.connections)&&state.connections.length===0&&document.querySelectorAll('#region-layer .canvas-region').length===0&&document.getElementById('relation-count').textContent==='0 条 · 手动标注'", "legacy missing graph fields hydrate as empty and project switch never leaks prior regions")
  print("PASS: isolated cold-start snapshot hydration checks; animation frames intentionally paused, no app shown, real projects, model, or keychain accessed")
 }
}

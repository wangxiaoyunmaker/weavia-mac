import AppKit
import WebKit
import CryptoKit

enum StartupFixture { static var script = "" }
@main struct WeaviaStartupRecoveryChecks {
 static var failures=0
 static var controllers:[MacWorkspaceCanvas]=[]
 static let dataStore=WKWebsiteDataStore.nonPersistent()
 static func spin(_ n:Double){RunLoop.current.run(until:Date().addingTimeInterval(n))}
 static func js(_ c:MacWorkspaceCanvas,_ script:String)throws->Any?{
  var done=false,value:Any?,error:Error?
  c.webView.evaluateJavaScript(script){value=$0;error=$1;done=true}
  let end=Date().addingTimeInterval(12);while !done && Date()<end{spin(0.02)}
  if let error{throw error};precondition(done);return value
 }
 static func quote(_ v:Any)throws->String{String(data:try JSONSerialization.data(withJSONObject:[v],options:[.sortedKeys]),encoding:.utf8)!.dropFirst().dropLast().description}
 static func raw(_ v:[String:Any])throws->String{String(data:try JSONSerialization.data(withJSONObject:v,options:[.sortedKeys]),encoding:.utf8)!}
 static func snapshot(_ count:Int,_ revision:Int,_ title:String="native")->[String:Any]{
  var cards:[[String:Any]]=[]
  for i in 0..<count {cards.append(["id":"fixture-\(i)","type":"source","title":"\(title)-\(i)","text":"Synthetic only","x":100+i*10,"y":100,"tags":[]])}
  let draft:[String:Any]=["text":"","sources":[],"refs":[]]
  let persistence:[String:Any]=["version":1,"revision":revision,"captureIds":[]]
  return ["cards":cards,"regions":[],"connections":[],"drafts":["personal":draft,"agent":draft],"mode":"personal","resourceSemanticVersion":1,"aiExcerptExamplesAdded":true,"_companionPersistence":persistence]
 }
 static func launch(_ project:String,cache:String?=nil,pending:String?=nil,base:String?=nil)throws->MacWorkspaceCanvas{
  var script="window.fixtureStorageWrites=[];const fixtureSet=Storage.prototype.setItem;Storage.prototype.setItem=function(k,v){window.fixtureStorageWrites.push({key:k,raw:String(v),beforeNative:!window.fixtureNativeHydrating});return fixtureSet.call(this,k,v);};"
  for (k,v) in [("design-canvas-v1:"+project,cache),("cuppa-mac-pending:"+project,pending),("cuppa-mac-pending-base:"+project,base)]{if let v{script += "localStorage.setItem(\(try quote(k)),\(try quote(v)));"}}
  script += "window.fixtureStorageWrites=[];"
  StartupFixture.script=script
  let context=CompanionContext();context.selectProject(project)
  let c=MacWorkspaceCanvas(context:context,websiteDataStore:dataStore);controllers.append(c);spin(4)
  precondition(!c.window.isVisible && !dataStore.isPersistent);return c
 }
 static func check(_ ok:Bool,_ label:String){if !ok{failures+=1};print("\(ok ? "PASS" : "FAIL"): \(label)")}
 static func count(_ s:MacCanvasSnapshotStore,_ p:String)throws->Int{(try s.load(p)?["cards"] as? [[String:Any]])?.count ?? -1}
 static func title(_ s:MacCanvasSnapshotStore,_ p:String)throws->String{(try s.load(p)?["cards"] as? [[String:Any]])?.first?["title"] as? String ?? ""}
 static func pagehide(_ c:MacWorkspaceCanvas)throws{_ = try js(c,"window.dispatchEvent(new Event('pagehide'));true");spin(0.7)}
 static func archives(_ root:URL)->[[String:Any]]{
  guard let e=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)else{return []}
  return e.compactMap{v in guard let u=v as? URL,let d=try? Data(contentsOf:u),let o=try? JSONSerialization.jsonObject(with:d) as? [String:Any],o["pendingRaw"] != nil || o["cachedRaw"] != nil else{return nil};return o}
 }
 static func main()throws{
  let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  setenv("MOUSE_COMPANION_PROJECTS_DIR",root.appendingPathComponent("Projects").path,1)
  setbuf(stdout,nil);_ = NSApplication.shared;let store=MacCanvasSnapshotStore()
  for n in [58,40]{
   let p="clean-\(n)-"+UUID().uuidString
   try store.save(snapshot(n,18),project:p)
   let c=try launch(p,cache:raw(snapshot(32,17,"cached")));try pagehide(c)
   check(try count(store,p)==n,"clean cached32 revision17 cannot replace native\(n) revision18 on initialization/pagehide")
   let writes=try js(c,"fixtureStorageWrites.filter(x=>x.key.startsWith('cuppa-mac-pending:')).length") as? Int ?? -1
   print("TRACE: clean native\(n), initialization pending writes=\(writes), disk count=\(try count(store,p))")
   check(try js(c,"fixtureStorageWrites.filter(x=>x.key.startsWith('cuppa-mac-pending:')).every(x=>!x.beforeNative && JSON.parse(x.raw).cards.length===\(n))") as? Bool==true,"initialization never stages pre-hydration or stale32 draft; native normalization is allowed")
   c.webView.configuration.userContentController.removeAllUserScripts();c.webView.reload();spin(3);try pagehide(c)
   check(try count(store,p)==n,"same WKWebsiteDataStore reload retains native\(n)")
  }
  let p="dirty-conflict-"+UUID().uuidString,old=try raw(snapshot(32,18,"old-dirty")),cached=try raw(snapshot(32,17,"old-cache"))
  try store.save(snapshot(58,18),project:p)
  let dirty=try launch(p,cache:cached,pending:old);try pagehide(dirty)
  check(try count(store,p)==58,"same-revision dirty old32 cannot replace native58")
  check(try js(dirty,"state.cards.length") as? Int==58,"conflict shows native58 rather than stale32")
  check(archives(root).contains{($0["pendingRaw"] as? String)==old && ($0["cachedRaw"] as? String)==cached},"durable archive preserves exact pendingRaw and cachedRaw")
  check(try js(dirty,"save()===false && localStorage.getItem('cuppa-mac-pending:'+projectId)===\(try quote(old)) && localStorage.getItem('design-canvas-v1:'+projectId)===\(try quote(cached))") as? Bool==true,"conflict stays read-only with exact active pending/cache preserved")
  let canContinue=try js(dirty,"!!document.getElementById('mac-recovery-continue') && !document.getElementById('mac-recovery-continue').disabled") as? Bool == true
  check(canContinue,"explicit continue enabled after durable archive acknowledgment")
  if canContinue{_ = try js(dirty,"document.getElementById('mac-recovery-continue').click();true");spin(0.5)}
  check(archives(root).contains{($0["pendingRaw"] as? String)==old},"continuing native retains archive")
  let matching="matching-base-"+UUID().uuidString,baseSnapshot=snapshot(40,18)
  let token=SHA256.hash(data:Data(try raw(baseSnapshot).utf8)).map{String(format:"%02x",$0)}.joined()
  try store.save(baseSnapshot,project:matching)
  let validRaw=try raw(snapshot(41,19,"valid-user-draft"))
  let valid=try launch(matching,cache:raw(baseSnapshot),pending:validRaw,base:token);try pagehide(valid)
  check(try count(store,matching)==41 && title(store,matching)=="valid-user-draft-0","matching baseCanvasToken restores valid pending user draft")
  check(try js(valid,"localStorage.getItem('cuppa-mac-pending:'+projectId)===null") as? Bool==true,"matching-base draft clears pending only after native acknowledgment")
  let equal="equal-native-"+UUID().uuidString,equalSnapshot=snapshot(40,18),equalRaw=try raw(equalSnapshot)
  try store.save(equalSnapshot,project:equal)
  let acknowledged=try launch(equal,cache:equalRaw,pending:equalRaw);try pagehide(acknowledged)
  check(try count(store,equal)==40 && js(acknowledged,"localStorage.getItem('cuppa-mac-pending:'+projectId)===null") as? Bool==true,"pending equal to native clears stale acknowledgment without conflict")
  let safe="multiple-saves-"+UUID().uuidString;try store.save(snapshot(40,18),project:safe)
  let c=try launch(safe)
  _ = try js(c,"state.cards[0].title='edit-one';save();state.cards[0].title='edit-two';save();state.cards[0].title='edit-newest';save();true");spin(2);try pagehide(c)
  check(try title(store,safe)=="edit-newest","multiple saves persist newest edit")
  let restarted=try launch(safe)
  check(try js(restarted,"state.cards[0].title") as? String=="edit-newest","new controller sharing WebKit store restores newest edit")
  try store.save(snapshot(58,50,"external-import"),project:safe)
  _ = try js(restarted,"state.cards[0].title='local-after-external';save();true");spin(1);try pagehide(restarted)
  check(try count(store,safe)==58 && title(store,safe)=="external-import-0","external native change after hydration rejects stale save")
  let retained=try js(restarted,"(localStorage.getItem('cuppa-mac-pending:'+projectId)||'').includes('local-after-external')") as? Bool == true
  check(retained || archives(root).contains{($0["pendingRaw"] as? String)?.contains("local-after-external")==true},"rejected save retains recoverable draft")
  for c in controllers{precondition(!c.window.isVisible)}
  print("RESULT: \(failures) failures; production JS/native storage, shared ephemeral WebKit, hidden windows, synthetic temp data only")
  if failures>0{exit(1)}
 }
}

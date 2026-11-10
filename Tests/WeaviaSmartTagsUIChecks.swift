import AppKit
import WebKit
@main struct WeaviaSmartTagsUIChecks {
 static func main() throws {
  setbuf(stdout,nil)
  let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  setenv("MOUSE_COMPANION_PROJECTS_DIR",root.appendingPathComponent("Projects").path,1)
  _ = NSApplication.shared
  let context=CompanionContext();context.selectProject("Smart tag isolated fixture " + UUID().uuidString)
  let controller=MacWorkspaceCanvas(context:context)
  var requests=0,cancels=0,lastRequest="",reply=true
  let rows=[["label":"标题层级","reason":"合成卡片的文字说明使用大号标题。"],["label":"留白","reason":"合成文字明确提到留白。"]]
  controller.onSmartTags={card,id in
   precondition(card["id"] as? String == "smart-fixture");requests+=1;lastRequest=id
   if reply { controller.receiveSmartTagResult(["requestId":id,"projectId":context.project,"ok":true,"suggestions":rows,"provider":"Synthetic fixture · not a live model","inputMode":"text_only"]) }
  }
  controller.onCancelSmartTags={_ in cancels+=1}
  func spin(_ s:Double){RunLoop.current.run(until:Date().addingTimeInterval(s))}
  func evaluate(_ script:String)throws->Any?{var done=false,value:Any?,error:Error?;controller.webView.evaluateJavaScript(script){value=$0;error=$1;done=true};let end=Date().addingTimeInterval(10);while !done && Date()<end{spin(0.03)};if let error{throw error};precondition(done);return value}
  func check(_ script:String,_ name:String)throws{guard try evaluate(script) as? Bool == true else{print("FAIL: "+name);exit(1)};precondition(!controller.window.isVisible);print("PASS: "+name)}
  spin(10)
  _ = try evaluate("location.hash='#cuppa';state.cards.push({id:'smart-fixture',type:'source',title:'校园咖啡节海报 · 合成验收素材',text:'大号无衬线标题与留白突出主次信息。',tags:['海报'],x:400,y:160});save();renderCards();true")
  spin(0.7)
  _ = try evaluate("document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish()});true");spin(0.2)
  try check("!document.getElementById('workspace').hidden&&document.getElementById('project-desktop').hidden", "offscreen route transition has completed")
  _ = try evaluate("showTagTools('smart-fixture');document.getElementById('tag-smart').click();true");spin(0.5)
  try check("document.querySelectorAll('.smart-tag-candidate').length===2&&!document.getElementById('tag-popover').hidden&&state.cards.find(c=>c.id==='smart-fixture').tags.length===1","real UI renders fixture candidates and never auto-adopts")
  precondition(requests==1)
  try check("(()=>{const p=document.getElementById('tag-popover').getBoundingClientRect();return p.width>250&&p.height>200&&p.left>=0&&p.right<=innerWidth&&p.top>=0&&p.bottom<=innerHeight&&document.getElementById('tag-smart-provider').textContent.includes('仅文字')})()","popover fits viewport and declares text-only input")
  if CommandLine.arguments.count>2 {
   var done=false;controller.webView.takeSnapshot(with:nil){image,error in defer{done=true};if let image,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent("smart-tags-candidates.png"))}else{print("SNAPSHOT: \(String(describing:error))")}};let end=Date().addingTimeInterval(10);while !done&&Date()<end{spin(0.03)}
  }
  _ = try evaluate("document.querySelector('[data-smart-label=\"0\"]').value='信息层级';document.querySelector('[data-smart-check=\"1\"]').checked=false;document.getElementById('tag-smart-adopt').click();true");spin(0.7)
  try check("(()=>{const c=state.cards.find(c=>c.id==='smart-fixture');return c.tags.join('|')==='海报|信息层级'&&c.smartTagHistory[0].tags[0].editedByUser===true&&document.getElementById('tag-smart-status').textContent.includes('保存到本机')&&document.querySelectorAll('.smart-tag-candidate').length===1})()","edited selection adopts only checked tag after native disk acknowledgement")
  let saved=try MacCanvasSnapshotStore().load(context.project)!
  let card=(saved["cards"] as! [[String:Any]]).first{$0["id"] as? String == "smart-fixture"}!
  precondition(card["tags"] as? [String] == ["海报","信息层级"])
  print("PASS: adopted labels survive native snapshot reload")
  _ = try evaluate("document.getElementById('tag-smart-manual').click();true")
  try check("!document.getElementById('tag-form').hidden&&document.getElementById('tag-smart-panel').hidden","manual tag editor stays available")
  reply=false
  _ = try evaluate("document.getElementById('tag-smart').click();true");spin(0.3)
  try check("document.getElementById('tag-smart-stop')!==null","in-progress task exposes Stop")
  _ = try evaluate("document.getElementById('tag-smart-stop').click();true");spin(0.3)
  precondition(cancels>0)
  controller.receiveSmartTagResult(["requestId":lastRequest,"projectId":context.project,"ok":true,"suggestions":rows]);spin(0.2)
  try check("document.getElementById('tag-smart-status').textContent.includes('已中止')&&state.cards.find(c=>c.id==='smart-fixture').tags.length===2","cancel discards late result and never writes labels")
  _ = try evaluate("document.getElementById('tag-smart-retry').click();true");spin(0.3)
  controller.receiveSmartTagResult(["requestId":lastRequest,"projectId":context.project,"ok":false,"message":"合成接口失败，未返回标签。"]);spin(0.3)
  try check("document.getElementById('tag-smart-status').textContent.includes('合成接口失败')&&document.querySelectorAll('.smart-tag-candidate').length===0","API errors remain explicit without fabricated candidates")
  print("PASS: hidden WKWebView, private fixture storage, no model/keychain/user application access")
 }
}

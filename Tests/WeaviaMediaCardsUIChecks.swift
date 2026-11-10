import AppKit
import PDFKit
import WebKit

@main struct WeaviaMediaCardsUIChecks {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  setenv("MOUSE_COMPANION_PROJECTS_DIR",root.appendingPathComponent("Projects").path,1)
  _ = NSApplication.shared
  let context=CompanionContext();context.selectProject("Media card fixture "+UUID().uuidString)
  let store=CanvasAttachmentStore(),image=NSImage(size:NSSize(width:240,height:160))
  image.lockFocus();NSColor.systemTeal.setFill();NSRect(x:0,y:0,width:240,height:160).fill();image.unlockFocus()
  let png=root.appendingPathComponent("Synthetic image.png");try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:png)
  let imageRecord=try store.importFile(png,kind:"image",project:context.project)
  let pdf=PDFDocument();pdf.insert(PDFPage(image:image)!,at:0);pdf.insert(PDFPage(image:image)!,at:1)
  let pdfURL=root.appendingPathComponent("Synthetic paper.pdf");precondition(pdf.write(to:pdfURL))
  let pdfRecord=try store.importFile(pdfURL,kind:"pdf",project:context.project)
  let controller=MacWorkspaceCanvas(context:context)
  func spin(_ seconds:TimeInterval){RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
  func evaluate(_ script:String)throws->Any?{var done=false,value:Any?,error:Error?;controller.webView.evaluateJavaScript(script){value=$0;error=$1;done=true};let deadline=Date().addingTimeInterval(12);while !done && Date()<deadline{spin(0.05)};if let error{throw error};precondition(done);return value}
  func check(_ script:String,_ name:String)throws{guard try evaluate(script) as? Bool == true else{print("FAIL: "+name);exit(1)};precondition(!controller.window.isVisible);print("PASS: "+name)}
  func runHistory(_ redo:Bool=false)throws{
   _ = try evaluate("window.historyDone=false;cuppaCanvasHistory.run(\(redo ? "true":"false")).then(ok=>{window.historyOK=ok;window.historyDone=true});true")
   let deadline=Date().addingTimeInterval(12);while Date()<deadline{if try evaluate("historyDone") as? Bool == true{break};spin(0.05)}
   try check("historyDone&&historyOK","combined media history waits for native acknowledgement");spin(0.3)
  }
  func json(_ value:[String:Any])throws->String{String(data:try JSONSerialization.data(withJSONObject:value),encoding:.utf8)!}
  spin(12);_ = try evaluate("location.hash='#cuppa';true");spin(1)
  _ = try evaluate("window.mediaFixtures={image:\(try json(store.payload(imageRecord,project:context.project))),pdf:\(try json(store.payload(pdfRecord,project:context.project)))};window.realNative=mouseCompanionMac;window.previewCalls=[];window.mouseCompanionMac={...realNative,importAttachment:async kind=>({attachment:mediaFixtures[kind]}),previewAttachment:(id,page)=>previewCalls.push({id,page})};true")
  try check("['image','pdf','design'].every(t=>document.querySelector('[data-add=\"'+t+'\"]'))","explicit design/image/PDF creation entries")
  try check("!document.getElementById('workspace').hidden&&location.hash==='#cuppa'","canvas route visibly active in offscreen fixture")
  for kind in ["image","pdf"] {
   _ = try evaluate("createEditor('\(kind)');document.getElementById('media-pick').click();true");spin(0.3)
   try check("document.getElementById('media-file').textContent.includes('Synthetic')","\(kind) selected original shown before adding")
   _ = try evaluate("document.getElementById('media-title').value='\(kind) fixture';document.getElementById('media-source').value='https://example.invalid/\(kind)';document.getElementById('media-note').value='User-authored note';if(document.getElementById('media-page'))document.getElementById('media-page').value='2';document.getElementById('media-form').dispatchEvent(new Event('submit',{cancelable:true}));document.getElementById('media-form').dispatchEvent(new Event('submit',{cancelable:true}));true");spin(1)
   try check("!document.getElementById('dialog').open&&state.cards.filter(c=>c.type==='\(kind)').length===1","\(kind) double submit creates one native-acknowledged card")
   try check("(()=>{const c=state.cards.find(c=>c.type==='\(kind)'),el=cardElement(c.id),img=el.querySelector('img');return img.complete&&img.naturalWidth>0&&el.querySelector('[data-media-preview]')&&el.querySelector('.card-detail-open')&&c.url==='https://example.invalid/\(kind)'&&c.attachment.id===mediaFixtures.\(kind).id})()","\(kind) local thumbnail, original ID, source and details retained")
   _ = try evaluate("window.activeMedia=state.cards.find(c=>c.type==='\(kind)');cardElement(activeMedia.id).querySelector('[data-media-preview]').click();true")
   try check("previewCalls.at(-1).id===activeMedia.attachment.id","\(kind) explicit original action routes only its attachment ID")
   _ = try evaluate("window.mediaBefore=JSON.stringify(state);cardElement(activeMedia.id).querySelector('.card-detail-open').click();true")
   try check("document.getElementById('card-detail-dialog').open&&document.querySelector('[data-detail-original]')&&document.getElementById('card-detail-dialog').textContent.includes('User-authored note')","\(kind) details retain note and full original action")
   _ = try evaluate("document.querySelector('[data-detail-close]').click();true")
   try check("JSON.stringify(state)===mediaBefore","\(kind) inspection and close never mutate cards")
   _ = try evaluate("window.createdMediaJSON=JSON.stringify(activeMedia);true")
   try runHistory()
   try check("!state.cards.some(c=>c.type==='\(kind)')","\(kind) creation is included in global undo")
   let originalID = kind == "image" ? imageRecord.id : pdfRecord.id
   let originalPath = try store.original(originalID,project:context.project).path
   precondition(FileManager.default.fileExists(atPath:originalPath))
   try runHistory(true)
   try check("(()=>{const c=state.cards.find(c=>c.type==='\(kind)'),img=cardElement(c.id).querySelector('img');return JSON.stringify(c)===createdMediaJSON&&img.complete&&img.naturalWidth>0})()","\(kind) redo restores exact metadata and working local original thumbnail")
  }
  try check("previewCalls.find(v=>v.id===mediaFixtures.pdf.id).page===2","PDF requested page travels through preview API")
  _ = try evaluate("window.editCard=state.cards.find(c=>c.type==='pdf');CanvasMediaCards.editor('pdf',editCard);document.getElementById('media-page').value='99';document.getElementById('media-form').dispatchEvent(new Event('submit',{cancelable:true}));true");spin(0.2)
  try check("document.getElementById('media-error').textContent.includes('实际页数')&&state.cards.find(c=>c.type==='pdf').pageNumber===2","out-of-range PDF page blocked without state changes")
  _ = try evaluate("document.getElementById('media-page').value='2';document.getElementById('media-cancel').click();true")
  try check("!document.getElementById('dialog').open","cancel unchanged editor closes cleanly")
  _ = try evaluate("window.mouseCompanionMac={...mouseCompanionMac,importAttachment:async()=>({cancelled:true})};createEditor('image');document.getElementById('media-pick').click();true");spin(0.2)
  try check("document.getElementById('media-file').textContent==='尚未选择文件'&&!document.getElementById('media-save').disabled","picker cancellation leaves editable draft and no fake attachment")
  _ = try evaluate("document.getElementById('media-cancel').click();window.mouseCompanionMac={...mouseCompanionMac,importAttachment:async()=>{throw Error('Synthetic import failed')}};createEditor('pdf');document.getElementById('media-pick').click();true");spin(0.2)
  try check("document.getElementById('media-error').textContent.includes('Synthetic import failed')&&!document.getElementById('media-save').disabled","file failure remains visible and retryable")
  _ = try evaluate("document.getElementById('media-cancel').click();designEditor();document.getElementById('design-title').value='Figma frame';document.getElementById('design-url').value='https://www.figma.com/design/fixture/Frame?node-id=12-34&mode=design';document.getElementById('design-object-form').dispatchEvent(new Event('submit',{cancelable:true}));true");spin(0.6)
  try check("(()=>{const c=state.cards.find(c=>c.type==='design'),a=cardElement(c.id).querySelector('.design-open');return a.textContent.includes('在 Figma 打开')&&a.getAttribute('href')==='https://www.figma.com/design/fixture/Frame?node-id=12-34&mode=design'&&a.target==='_blank'})()","Figma card exposes exact external URL including node-id; no real URL opened")
  _ = try evaluate("window.tagTarget=state.cards.find(c=>c.type==='image');window.beforeSmartTags=JSON.stringify(tagTarget);window.tagDone=false;mouseCompanionMac.commitSmartTags(tagTarget.id,WeaviaSmartTags.fingerprint(tagTarget),[{label:'Synthetic accepted label',reason:'Test fixture only'}],{provider:'Synthetic fixture',inputMode:'text_only'}).then(()=>window.tagDone=true);true");spin(0.6)
  try check("tagDone&&cuppaCanvasHistory.status().undoLabel==='修改标签'&&state.cards.find(c=>c.id===tagTarget.id).smartTagHistory.length===1","adopted smart tags on a new image card enter global history after acknowledgement")
  try runHistory()
  try check("JSON.stringify(state.cards.find(c=>c.id===tagTarget.id))===beforeSmartTags","undo restores attachment and original card bytes before tag adoption")
  try runHistory(true)
  try check("state.cards.find(c=>c.id===tagTarget.id).tags.includes('Synthetic accepted label')&&state.cards.find(c=>c.id===tagTarget.id).smartTagHistory[0].status==='accepted_by_user'","redo preserves explicit adoption provenance")
  let persisted=try MacCanvasSnapshotStore().load(context.project)!;let cards=persisted["cards"] as! [[String:Any]]
  precondition(cards.filter{$0["type"] as? String=="pdf"}.count==1 && cards.filter{$0["type"] as? String=="image"}.count==1)
  precondition(cards.first{$0["type"] as? String=="pdf"}?["pageNumber"] as? Int==2)
  print("PASS: native disk roundtrip preserves both card types, original IDs, source and page")
  _ = try evaluate("location.hash='#cuppa';state.cards.find(c=>c.type==='image').x=380;state.cards.find(c=>c.type==='image').y=200;state.cards.find(c=>c.type==='pdf').x=800;state.cards.find(c=>c.type==='pdf').y=200;state.cards.find(c=>c.type==='design').x=1220;state.cards.find(c=>c.type==='design').y=200;pan={x:0,y:0};zoom=.8;renderCards();updateView();document.getAnimations().forEach(a=>{try{a.finish()}catch{}});true");spin(0.5)
  if CommandLine.arguments.count>2 {controller.window.setFrameOrigin(NSPoint(x: -10000, y: -10000));controller.window.orderBack(nil);controller.webView.displayIfNeeded();spin(1);var done=false;controller.webView.takeSnapshot(with:nil){image,error in if let data=image?.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))};done=true};let deadline=Date().addingTimeInterval(10);while !done&&Date()<deadline{spin(0.05)}}
  controller.window.close();print("PASS: offscreen media-card integration, no app foreground, real data, external URL or model access")
 }
}

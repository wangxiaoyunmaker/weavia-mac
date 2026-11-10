import AppKit
import WebKit

@main struct WeaviaCardDetailsChecks {
 static func main() throws {
  let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
  setenv("MOUSE_COMPANION_PROJECTS_DIR", root.appendingPathComponent("Projects").path, 1)
  _ = NSApplication.shared
  let context = CompanionContext()
  context.selectProject("Card details fixture " + UUID().uuidString)
  let materialID = "00000000-0000-4000-8000-000000000001"
  context.upsert(CompanionMaterial(id: materialID, project: context.project, title: "Native fixture", text: "Native original full text", note: "Native note", area: "Fixture", image: nil, saved: true))
  let controller = MacWorkspaceCanvas(context: context)
  var opened: [String] = []
  controller.onOpenMaterial = { opened.append($0) }
  func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
  func evaluate(_ script: String) throws -> Any? {
   var done = false, value: Any?, failure: Error?
   controller.webView.evaluateJavaScript(script) { value = $0; failure = $1; done = true }
   let deadline = Date().addingTimeInterval(10)
   while !done && Date() < deadline { spin(0.05) }
   if let failure { throw failure }; if !done { throw NSError(domain:"DetailsCheck",code:1) }; return value
  }
  func check(_ script: String, _ name: String) throws {
   guard try evaluate(script) as? Bool == true else { print("FAIL: \(name)"); exit(1) }
   precondition(!controller.window.isVisible); print("PASS: \(name)")
  }
  spin(12)
  _ = try evaluate("document.getElementById('open-cuppa').click(); true")
  spin(1)
  try check("!!CuppaCardDetails && document.querySelectorAll('#selection-details').length===1", "detail module and unique companion option load")
  _ = try evaluate("state.cards.find(c=>c.nativeMaterialId)&&document.querySelector('.card .card-detail-open').click(); true")
  spin(0.5)
  precondition(opened == [materialID], "Native card must route original Mac detail")
  print("PASS: native card button invokes existing Mac material detail")
  _ = try evaluate("""
  window.detailFixtures=[
   {id:'detail-source',type:'source',title:'Full source',text:'Full source text\\nLAST LINE',provenance:{sourceLabel:'Synthetic browser',excerpt:'Full source text\\nLAST LINE'},url:'https://example.invalid/source',userNote:'A private fixture note',tags:['fixture'],x:320,y:180},
   {id:'detail-ai',type:'source',title:'AI excerpt',text:'Saved AI text',tags:[],x:700,y:180,ai:{version:1,provider:'unknown',threadId:'fixture-thread',mode:'excerpt',originalText:'AI ORIGINAL LAST LINE',question:'Original question',blocks:[{type:'paragraph',text:'AI ORIGINAL LAST LINE'}]}},
   {id:'detail-claim',type:'claim',title:'Claim',text:'Claim full text',blocks:[{id:'b1',type:'text',text:'Claim full text'},{id:'b2',type:'table',cells:[['A','B'],['C','D']]},{id:'b3',type:'doodle',strokes:[{id:'s1',points:[[0,0],[20,20]]}]}],x:320,y:480,tags:[]},
   {id:'detail-design',type:'design',title:'Design object',text:'Full design note',designObject:{version:1,sourceApp:'Fixture Figma',originalUrl:'https://example.invalid/design',location:'Page / Frame / Layer'},x:700,y:480,tags:['layout']}
  ];
  state.cards.push(...detailFixtures); state.aiThreads=state.aiThreads||[];renderCards();
  window.detailsBefore=JSON.stringify(state); true
  """)
  try check("detailFixtures.every(c=>cardElement(c.id).querySelector('.card-detail-open'))", "all four card types expose a detail button")
  for (id, text) in [("detail-source","LAST LINE"),("detail-ai","AI ORIGINAL LAST LINE"),("detail-claim","Claim full text"),("detail-design","Page / Frame / Layer")] {
   try check("(()=>{cardElement('\(id)').querySelector('.card-detail-open').click();const d=document.getElementById('card-detail-dialog');return d.open&&d.textContent.includes('\(text)')})()", "\(id) opens preserved full content")
   try check("(()=>{document.querySelector('[data-detail-close]').click();return !document.getElementById('card-detail-dialog').open&&JSON.stringify(state)===detailsBefore})()", "\(id) close preserves snapshot")
   try check("(()=>{cardElement('\(id)').dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));return document.getElementById('card-detail-dialog').open})()", "\(id) doubleclick reopens details")
   try check("(()=>{document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return !document.getElementById('card-detail-dialog').open&&JSON.stringify(state)===detailsBefore})()", "\(id) Escape closes without mutation")
  }
  try check("(()=>{const el=cardElement('detail-source');el.click();return selected==='detail-source'&&!document.getElementById('card-detail-dialog').open})()", "single click only selects; no detail modal")
  try check("(()=>{const el=cardElement('detail-source');el.dispatchEvent(new PointerEvent('pointerdown',{clientX:5,clientY:5,button:0,bubbles:true}));el.dispatchEvent(new PointerEvent('pointermove',{clientX:8,clientY:7,bubbles:true}));el.dispatchEvent(new PointerEvent('pointerup',{clientX:8,clientY:7,bubbles:true}));el.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));return document.getElementById('card-detail-dialog').open})()", "small doubleclick jitter under 4px still opens details")
  _ = try evaluate("document.querySelector('[data-detail-close]').click(); true")
  try check("(()=>{const el=cardElement('detail-source');el.dispatchEvent(new PointerEvent('pointerdown',{clientX:5,clientY:5,button:0,bubbles:true}));el.dispatchEvent(new PointerEvent('pointermove',{clientX:35,clientY:35,bubbles:true}));el.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));return !document.getElementById('card-detail-dialog').open})()", "drag gesture does not open detail or legacy editor")
  try check("(()=>{marqueeIds.clear();selected='detail-design';document.getElementById('selection-details').click();return document.getElementById('card-detail-dialog').open&&document.getElementById('card-detail-dialog').textContent.includes('Full design note')})()", "companion option opens selected card details")
  _ = try evaluate("document.querySelector('[data-detail-close]').click(); true")
  try check("(()=>{const el=cardElement('detail-claim').querySelector('[contenteditable]');el.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));return !document.getElementById('card-detail-dialog').open})()", "editable claim text retains native doubleclick text selection")
  try check("(()=>{const html=CuppaCardDetails.markup({title:'<img onerror=x>',text:'<script>x</script>',url:'javascript:alert(1)',tags:[]});return html.includes('&lt;script&gt;')&&!html.includes('<script>')&&!html.includes('javascript:')})()", "detail safely escapes content and rejects unsafe links")
  _ = try evaluate("""
  CuppaCardDetails.open({id:'image-fixture',type:'source',title:'Synthetic image',text:'Image preserved',image:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jX1sAAAAASUVORK5CYII=',tags:[]}); true
  """)
  spin(0.5)
  try check("(()=>{const image=document.querySelector('#card-detail-dialog .card-detail-image');return image.complete&&image.naturalWidth===1})()", "saved image rendered in full-detail reader")
  _ = try evaluate("document.querySelector('[data-detail-close]').click(); CuppaCardDetails.open(state.cards.find(c=>c.id==='detail-source')); true")
  try check("(()=>{const d=document.getElementById('card-detail-dialog');return d.textContent.includes('A private fixture note')&&d.textContent.includes('Synthetic browser')&&d.textContent.includes('fixture')&&d.querySelector('a').href==='https://example.invalid/source'})()", "source, tags, notes and original source link retained")
  try check("(()=>{document.querySelector('[data-detail-edit]').click();return !document.getElementById('card-detail-dialog').open&&document.getElementById('dialog').open&&!!document.getElementById('resource-form')})()", "existing resource edit action remains accessible")
  try check("(()=>{document.getElementById('dialog').close();return JSON.stringify(state)===detailsBefore})()", "canceling resource editor after viewing does not write card data")
  if CommandLine.arguments.count > 2 {
   controller.window.setContentSize(NSSize(width:1280,height:820))
   controller.webView.frame = NSRect(x:0,y:0,width:1280,height:820)
   _ = try evaluate("""
   CuppaCardDetails.open({type:'source',title:'设计调研：收集灵感时保留完整上下文',text:'一张卡片不仅要呈现摘要，也应让设计师随时回看保存的原文。\\n\\n通过明确的“查看详情”入口，用户可以阅读完整材料、核对来源，并保留自己的批注。单击选中与伙伴输入仍然维持原有交互。\\n\\n此处所有文字均为离屏测试生成的合成材料，不包含用户数据。',provenance:{sourceLabel:'合成设计研究 · 本机测试',capturedAt:'2026-11-10 14:30'},url:'https://example.invalid/research',tags:['设计研究','交互细节'],userNote:'后续对比完整阅读与卡片摘要的使用体验。'});document.getAnimations().forEach(a=>a.finish());true
   """)
   spin(1)
   var snapshotDone = false, snapshotError: Error?
   controller.webView.takeSnapshot(with:nil) { image, error in
    defer { snapshotDone = true }; snapshotError = error
    do {
     guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data:data), let png = bitmap.representation(using:.png,properties:[:]) else { throw NSError(domain:"DetailSnapshot",code:1) }
     try png.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
    } catch { snapshotError = error }
   }
   let deadline = Date().addingTimeInterval(10)
   while !snapshotDone && Date() < deadline { spin(0.05) }
   if let snapshotError { throw snapshotError }; precondition(snapshotDone)
   print("SNAPSHOT: \(CommandLine.arguments[2])")
  }
  print("PASS: isolated offscreen card-detail integration complete; no app launch, real data or API access")
 }
}

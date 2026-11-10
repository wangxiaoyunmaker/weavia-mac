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
  try check("(()=>{const el=cardElement('detail-source');el.dispatchEvent(new PointerEvent('pointerdown',{clientX:5,clientY:5,button:0,bubbles:true}));el.dispatchEvent(new PointerEvent('pointermove',{clientX:35,clientY:35,bubbles:true}));el.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));return !document.getElementById('card-detail-dialog').open})()", "drag gesture does not open detail or legacy editor")
  try check("(()=>{marqueeIds.clear();selected='detail-design';document.getElementById('selection-details').click();return document.getElementById('card-detail-dialog').open&&document.getElementById('card-detail-dialog').textContent.includes('Full design note')})()", "companion option opens selected card details")
  _ = try evaluate("document.querySelector('[data-detail-close]').click(); true")
  try check("(()=>{const el=cardElement('detail-claim').querySelector('[contenteditable]');el.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));return !document.getElementById('card-detail-dialog').open})()", "editable claim text retains native doubleclick text selection")
  try check("(()=>{const html=CuppaCardDetails.markup({title:'<img onerror=x>',text:'<script>x</script>',url:'javascript:alert(1)',tags:[]});return html.includes('&lt;script&gt;')&&!html.includes('<script>')&&!html.includes('javascript:')})()", "detail safely escapes content and rejects unsafe links")
  print("PASS: isolated offscreen card-detail integration complete; no app launch, real data or API access")
 }
}

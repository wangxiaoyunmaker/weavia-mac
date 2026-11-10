import AppKit
import WebKit

@main struct WeaviaRelationZoomChecks {
 static func main() throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: CommandLine.arguments[1])
  let config = WKWebViewConfiguration()
  config.websiteDataStore = .nonPersistent()
  let web = WKWebView(frame: NSRect(x:0,y:0,width:1000,height:700), configuration:config)
  func read(_ name:String)throws->String {try String(contentsOf:root.appendingPathComponent(name),encoding:.utf8)}
  let css = try read("style.css") + read("card-relations.css")
  web.loadHTMLString("<html><head><style>\(css)</style></head><body><div id='workspace' style='position:absolute;inset:0'><svg id='connection-layer'></svg><div id='region-layer'></div><div id='world'><div class='card' data-id='a' style='left:40px;top:50px;width:100px;height:80px'></div><div class='card' data-id='b' style='left:650px;top:450px;width:100px;height:80px'></div></div></div></body></html>",baseURL:nil)
  func spin(){RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
  let deadline=Date().addingTimeInterval(15)
  while web.isLoading && Date()<deadline {spin()}
  func evaluate(_ script:String)throws->Any? {
   var done=false,result:Any?,failure:Error?
   web.evaluateJavaScript(script){result=$0;failure=$1;done=true}
   let end=Date().addingTimeInterval(10)
   while !done && Date()<end {spin()}
   if let failure {throw failure};precondition(done,"JavaScript timeout");return result
  }
  _ = try evaluate("""
   const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
   let zoom=1,selected=null,pan={x:0,y:0};
   const state={cards:[{id:'a',title:'A'},{id:'b',title:'B'}],connections:[]};
   function esc(s){return String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;')}
   function syncMarqueeSelection(){} function positionTagTools(){}
   true
  """)
  for name in ["card-relations.js","card-relations-ui.js","canvas-interactions.js"] {_ = try evaluate(try read(name))}
  _ = try evaluate("""
   let opened=[];relationEditor=id=>opened.push(id);
   state.connections=[{id:'legacy',from:'a',to:'b'}, ...['related','similar','different','complementary','conflicting','custom'].map(kind=>({id:kind,from:'a',to:'b',relation:{version:1,source:'user',kind,customLabel:kind==='custom'?'参考':'',evidence:'Synthetic evidence',status:'confirmed',history:[]}})),{id:'assistant',from:'a',to:'b',relation:{version:1,source:'assistant',kind:'similar',customLabel:'',evidence:'Synthetic pending',status:'pending',history:[]}},{id:'future',from:'a',to:'b',relation:{version:999}}];
   const original=JSON.stringify(state); const baseline={};
   function check(ok,message){if(!ok)throw Error(message)}
   function testZoom(z){
    zoom=z;drawGraph();
    const edges=$$('.relation-edge');check(edges.length===9,'all edges retained');
    edges.forEach(g=>{
     const hidden=getComputedStyle(g.querySelector('.relation-edge-label')).display==='none';
     check(hidden===(z<.65),'pill visibility '+z+' '+g.dataset.edge);
     check(getComputedStyle(g.querySelector('.edge-hit')).pointerEvents==='stroke','hit path retained');
     check(getComputedStyle(g.querySelector('.edge-visible')).display!=='none','line visible');
     const color=getComputedStyle(g.querySelector('.edge-visible')).stroke;
     if(baseline[g.dataset.edge])check(color===baseline[g.dataset.edge],'color stable');else baseline[g.dataset.edge]=color;
     check(g.getAttribute('aria-label').includes('按 Enter 查看')&&g.querySelector('title').textContent,'details accessible');
     g.querySelector('.edge-hit').dispatchEvent(new MouseEvent('click',{bubbles:true}));
     check(opened.pop()===g.dataset.edge,'click edit');
     for(const key of ['Enter',' ']){g.dispatchEvent(new KeyboardEvent('keydown',{key,bubbles:true}));check(opened.pop()===g.dataset.edge,'keyboard edit');}
    });
    check(document.querySelector('[data-edge="custom"] .relation-arrow'),'arrow retained');
    check(document.querySelector('[data-edge="similar"] .relation-parallel'),'parallel retained');
    check(JSON.stringify(state)===original,'read-only zoom');
    activeEdge=null;return true;
   };
   true
  """)
  for zoom in [1.0,0.649,0.65,0.2,0.5,1.0,0.649,1.0] {
   let passed = try evaluate("testZoom(\(zoom))") as? Bool
   precondition(passed == true)
   print("PASS: offscreen WKWebView zoom \(zoom), labels, colors, hit targets, keyboard, directions and unchanged synthetic data")
  }
  let selectedPassed = try evaluate("""
   activeEdge='custom';zoom=1;drawGraph();
   let edge=document.querySelector('[data-edge="custom"]');
   const selectedColor=getComputedStyle(edge.querySelector('.edge-visible')).stroke;
   zoom=.5;drawGraph();edge=document.querySelector('[data-edge="custom"]');
   check(edge.classList.contains('edge-selected'),'selected state retained');
   check(getComputedStyle(edge.querySelector('.relation-edge-label')).display==='none','selected overview still uncluttered');
   check(getComputedStyle(edge.querySelector('.edge-visible')).stroke===selectedColor,'selected stroke retained');
   check(getComputedStyle(edge.querySelector('.edge-visible')).strokeWidth==='3px','selected width retained');
   edge.querySelector('.edge-hit').dispatchEvent(new MouseEvent('click',{bubbles:true}));
   check(opened.pop()==='custom','selected edge click entry');
   zoom=1;drawGraph();check(getComputedStyle(document.querySelector('[data-edge="custom"] .relation-edge-label')).display!=='none','selected detail restored');
   true
  """) as? Bool
  precondition(selectedPassed == true)
  print("PASS: selected edge retains emphasis and editor entry; label returns at normal zoom")
  precondition(web.window == nil)
  print("PASS: isolated nonpersistent WKWebView; no application window, native bridge, project storage or network used")
 }
}

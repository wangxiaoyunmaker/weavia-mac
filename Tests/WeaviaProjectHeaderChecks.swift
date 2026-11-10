import AppKit
import WebKit

@main struct WeaviaProjectHeaderChecks {
 static func main() throws {
  let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  setenv("MOUSE_COMPANION_PROJECTS_DIR",root.appendingPathComponent("Projects").path,1)
  setbuf(stdout,nil)
  _ = NSApplication.shared
  let context=CompanionContext(); context.selectProject("Coffee Companion")
  let controller=MacWorkspaceCanvas(context:context)
  var settings=0,history=0
  controller.onSettings={settings += 1};controller.onHistory={history += 1}
  func spin(_ seconds:Double){RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
  func evaluate(_ script:String)throws->Any?{
   var done=false,value:Any?,failure:Error?
   controller.webView.evaluateJavaScript(script){value=$0;failure=$1;done=true}
   let deadline=Date().addingTimeInterval(10)
   while !done && Date()<deadline {spin(0.05)}
   if let failure {throw failure};precondition(done);return value
  }
  func check(_ script:String,_ label:String)throws{
   guard try evaluate(script) as? Bool == true else {print("FAIL: \(label)");exit(1)}
   precondition(!controller.window.isVisible); print("PASS: \(label)")
  }
  spin(10)
  for name in ["Coffee Companion","咖啡伙伴跨语言设计研究 Coffee Companion International Design Research and Collaborative Material Collection"] {
   context.selectProject(name);spin(4)
   _ = try evaluate("location.hash='#cuppa';true");spin(0.5)
   _ = try evaluate("""
    window.headerCheck=()=>{
     document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish()});
     const collapsed=document.getElementById('sidebar').hidden;
     const h=document.querySelector(collapsed?'#collapsed-project':'#sidebar .project');
     const title=h.querySelector('[data-project-name]'),tr=title.getBoundingClientRect(),hr=h.getBoundingClientRect();
     const buttons=[...h.querySelectorAll('button')],rects=buttons.map(e=>e.getBoundingClientRect());
     const overlaps=(a,b)=>a.left<b.right-.5&&a.right>b.left+.5&&a.top<b.bottom-.5&&a.bottom>b.top+.5;
     const search=document.getElementById('search-shell').getBoundingClientRect();
     return title.textContent===title.title && title.scrollWidth<=title.clientWidth+1 && title.scrollHeight<=title.clientHeight+1 && getComputedStyle(title).whiteSpace==='normal'
      && hr.right<=innerWidth && hr.bottom<=innerHeight && !overlaps(hr,search)
      && buttons.length===4 && buttons.every((e,i)=>e.getAttribute('aria-label')&&e.querySelector('svg,img')&&!e.textContent.trim()&&rects[i].width===32&&rects[i].height===32)
      && rects.every((r,i)=>r.left>=hr.left&&r.right<=hr.right&&r.top>=hr.top&&r.bottom<=hr.bottom&&!overlaps(r,tr)&&rects.every((r2,j)=>i===j||!overlaps(r,r2)));
    };true
   """)
   for size in [NSSize(width:1280,height:820),NSSize(width:900,height:600)] {
    controller.window.setContentSize(size);controller.webView.frame=NSRect(origin:.zero,size:size);spin(0.5)
    for collapsed in [false,true] {
     _ = try evaluate("document.getElementById('\(collapsed ? "collapse" : "expand")').click();true");spin(0.2)
     try check("headerCheck()","full title and four nonoverlapping 32px vector controls: \(name), \(size), collapsed=\(collapsed)")
     let details=try evaluate("JSON.stringify([...document.querySelectorAll('[data-project-name]')].map(e=>({title:e.textContent,rect:e.getBoundingClientRect().toJSON()})))")
     print("LAYOUT: \(details ?? "nil")")
     if CommandLine.arguments.count > 2 {
      var done=false
      controller.webView.takeSnapshot(with:nil){image,error in
       defer{done=true}
       if let image,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]) {
        let filename="header-\(name == "Coffee Companion" ? "normal" : "long")-\(Int(size.width))-\(collapsed ? "collapsed" : "expanded").png"
        try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent(filename))
       } else {print("SNAPSHOT_LIMITATION: \(String(describing:error))")}
      }
      let deadline=Date().addingTimeInterval(10);while !done && Date()<deadline{spin(0.05)}
     }
     let oldSettings=settings,oldHistory=history
     _ = try evaluate("document.getElementById('\(collapsed ? "open-settings-collapsed" : "open-settings")').click();true");spin(0.7)
     let settingsDeadline=Date().addingTimeInterval(5);while settings==oldSettings && Date()<settingsDeadline{spin(0.1)}
     precondition(settings==oldSettings+1,"Settings callback failed")
     _ = try evaluate("document.getElementById('\(collapsed ? "history-collapsed" : "history")').click();true");spin(0.3)
     precondition(history==oldHistory+1,"History callback failed")
     _ = try evaluate("document.getElementById('\(collapsed ? "projects-collapsed" : "projects")').click();true");spin(0.3)
     _ = try evaluate("document.getAnimations().forEach(a=>{if(Number.isFinite(a.effect.getComputedTiming().endTime))a.finish()});true");spin(0.1)
     try check("location.hash!=='#cuppa' && document.getElementById('workspace').hidden","back route from both header states")
     _ = try evaluate("location.hash='#cuppa';true");spin(0.3)
     try check("headerCheck()","return keeps title, icons and action hit areas")
     print("PASS: native settings/history callbacks; offscreen window remains hidden")
    }
   }
  }
  print("PASS: WeaviaProjectHeaderChecks completed with isolated synthetic projects; no API, keychain, or user app launch")
 }
}

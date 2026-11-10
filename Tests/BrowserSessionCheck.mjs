import {execFileSync} from 'node:child_process';
const script = source => execFileSync('/usr/bin/osascript', ['-e', source], {encoding:'utf8', timeout:30000}).trim();
const quote = value => '"' + value.replaceAll('\\','\\\\').replaceAll('"','\\"').replaceAll('\n','\\n') + '"';
let windowID, oldIndex;
try {
  const chosen = script(`tell application "Google Chrome"
    repeat with w in windows
      repeat with i from 1 to count of tabs of w
        if URL of tab i of w starts with "https://www.xiaohongshu.com/" then
          set saved to active tab index of w
          set active tab index of w to i
          return {id of w, saved}
        end if
      end repeat
    end repeat
  end tell`);
  [windowID, oldIndex] = chosen.split(',').map(Number);
  if (!windowID || !oldIndex) throw Error('No open Xiaohongshu tab');
  const inspect = `(() => {
    const a = Array.from(document.querySelectorAll('.note-item a[href*="/explore/"]')).find(a => {const r=a.getBoundingClientRect(); return r.width>20 && r.height>20 && r.top>=0 && r.bottom<innerHeight;});
    if(!a) return JSON.stringify({found:false});
    const card=a.closest('.note-item'), box=(card.querySelector('.title') || a).getBoundingClientRect();
    return JSON.stringify({found:true,url:a.href,title:card.querySelector('.title')?.innerText.trim(),x:screenX+box.left+box.width/2,y:screenY+(outerHeight-innerHeight)+box.top+box.height/2});
  })()`;
  const value = JSON.parse(script(`tell application "Google Chrome" to execute active tab of window id ${windowID} javascript ${quote(inspect)}`));
  if(!value.found || !value.title) throw Error('No visible reference card to validate');
  if(process.argv.includes('--drag')) {
    script('tell application "Google Chrome" to activate');
    const swift = `import CoreGraphics; import Foundation
      let start=CGPoint(x:${value.x},y:${value.y}), end=CGPoint(x:1100,y:390)
      CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:start,mouseButton:.left)?.post(tap:.cghidEventTap)
      usleep(200000)
      CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:start,mouseButton:.left)?.post(tap:.cghidEventTap)
      usleep(250000)
      for index in 1...40 { let t=CGFloat(index)/40; let p=CGPoint(x:start.x+(end.x-start.x)*t,y:start.y+(end.y-start.y)*t); CGEvent(mouseEventSource:nil,mouseType:.leftMouseDragged,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap); usleep(40000) }
      usleep(500000)
      CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:end,mouseButton:.left)?.post(tap:.cghidEventTap)`;
    execFileSync('/usr/bin/swift', ['-e', swift], {timeout:10000});
    await new Promise(resolve=>setTimeout(resolve,10000));
    const state=script('tell application "System Events" to tell process "Mouse Companion" to get entire contents of every window');
    console.log(JSON.stringify({titleVisible:state.includes(value.title),sourceFromBrowser:state.includes('来自当前浏览器页面'),needsAction:state.includes('浏览器预览待完成')}));
  } else {
    const result = execFileSync('/tmp/mouse-companion-browser-session-checks', [value.url, String(value.x), String(value.y), value.title], {encoding:'utf8', timeout:25000});
    process.stdout.write(result);
  }
} finally {
  if(windowID && oldIndex) script(`tell application "Google Chrome" to set active tab index of window id ${windowID} to ${oldIndex}`);
}

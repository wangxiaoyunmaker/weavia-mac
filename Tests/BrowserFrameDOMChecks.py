"""Exercise matching and mismatching same-origin note frames in real Chrome."""
import json
from pathlib import Path
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*_): pass
    def do_GET(self):
        if self.path.startswith('/parent') or 'utm_source=wrapper' in self.path:
            html = "<title>搜索页外壳</title><iframe src='/other' style='width:80px;height:80px'></iframe><iframe id='note-frame' src='/note' style='position:absolute;left:100px;top:120px;width:400px;height:350px;border:0'></iframe>"
        elif self.path == '/mismatch':
            html = "<iframe id='note-frame' src='/redirect' style='width:400px;height:350px'></iframe>"
        elif self.path == '/redirect':
            self.send_response(302); self.send_header('Location','/other'); self.end_headers(); return
        elif self.path == '/note':
            html = "<div id='noteContainer'><h1 id='detail-title'>内嵌笔记</h1><div id='detail-desc'>MATCHING_FRAME_BODY：先试用，再追问。</div></div>"
        else:
            html = "<div id='noteContainer'><h1 id='detail-title'>另一篇</h1><div id='detail-desc'>OTHER_FRAME_DO_NOT_READ</div></div>"
        data=html.encode(); self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
def apple(script): return subprocess.check_output(['osascript','-e',script],text=True,timeout=10).strip()
server=ThreadingHTTPServer(('127.0.0.1',0),Handler); threading.Thread(target=server.serve_forever,daemon=True).start()
wid=None
try:
    wid=int(apple('tell application "Google Chrome" to return id of (make new window)'))
    base=f'http://127.0.0.1:{server.server_port}'
    body=Path('Sources/MouseCompanion/BrowserCapture.js').read_text()
    cases=[('/parent','/note',True),('/note?utm_source=wrapper','/note',True),('/mismatch','/redirect',False)]
    for page,target,expected in cases:
        apple(f'tell application "Google Chrome" to set URL of active tab of window id {wid} to '+json.dumps(base+page))
        deadline=time.monotonic()+8
        result={}
        while time.monotonic()<deadline:
            time.sleep(0.15)
            if not expected:
                query = "JSON.stringify({path:document.querySelector('iframe')?.contentWindow.location.pathname,ready:document.querySelector('iframe')?.contentDocument.readyState})"
                state = json.loads(apple(f'tell application "Google Chrome" to execute active tab of window id {wid} javascript '+json.dumps(query)))
                if state.get('path') != '/other' or state.get('ready') != 'complete': continue
            js='(()=>{const CAPTURE_INPUT='+json.dumps({'url':base+target,'x':-1000,'y':-1000})+';return '+body+'})()'
            try: result=json.loads(apple(f'tell application "Google Chrome" to execute active tab of window id {wid} javascript '+json.dumps(js,ensure_ascii=False)))
            except ValueError: continue
            if expected and result.get('text') == 'MATCHING_FRAME_BODY：先试用，再追问。': break
            if not expected and result.get('matched') is False: break
        assert bool(result.get('matched')) == expected, result
        if expected:
            assert result.get('inFrame') and result['textSource']=='browser_note_body', result
            assert result['contentURL']==base+'/note'
            assert 'OTHER_FRAME' not in result['text']
        else:
            assert not result.get('text')
    print('PASS: matching same-origin iframe, matching outer shell with nested body, different-note frame exclusion and frame redirect mismatch')
finally:
    if wid is not None:
        try: apple(f'tell application "Google Chrome" to close window id {wid}')
        except Exception: pass
    server.shutdown()

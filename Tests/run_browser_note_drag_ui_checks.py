"""Real Chrome link drag; separate localhost window, fake API key, isolated project."""
import base64
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

requests = []
# Generate a small local PNG; no external site, image or account content is used.
def chunk(name, data): return struct.pack('>I',len(data))+name+data+struct.pack('>I',zlib.crc32(name+data)&0xffffffff)
png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',80,80,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes([90,150,245])*80)*80))+chunk(b'IEND',b'')
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*_): pass
    def do_GET(self):
        html = f'''<html><title>浏览器正文拖拽测试</title><style>body{{font:16px sans-serif;padding:12px}}a{{display:block;float:right}}img{{width:80px;height:80px}}#detail-desc{{clear:both;padding-top:16px}}</style>
        <div id="noteContainer"><h1 id="detail-title">访谈组织经验笔记</h1><a id="drag-note" title="访谈组织经验笔记" href="/note"><img src="data:image/png;base64,{base64.b64encode(png).decode()}"></a>
        <div id="detail-desc"><p>BROWSER_NOTE_BODY_SENTINEL：先让参与者试用，再追问行为原因，最后记录反例。</p><p>这是一份访谈组织经验，效果仍需验证，不是配色或排版教程。</p></div><section class="comment-list">无关评论不要进入正文</section></div></html>'''.encode()
        self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Content-Length',str(len(html))); self.end_headers(); self.wfile.write(html)
    def do_POST(self):
        assert self.headers['Authorization'] == 'Bearer fixture-only'
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        content = body['input'][0]['content'] if isinstance(body['input'],list) else []
        value = json.loads(content[0]['text'] if content else body['input'])
        assert 'BROWSER_NOTE_BODY_SENTINEL' in value['material']['text'], value['material']
        assert '无关评论' not in value['material']['text']
        assert value['material']['text_source'] == 'browser_note_body' and value['material']['note_body_available']
        assert value['allowed_skills'] == ['content-understanding','reference-transfer']
        requests.append(value)
        data = json.dumps({'output_text':json.dumps({'suggestions':[
            {'label':'复用三步访谈结构','reason':'正文给出了试用、追问、记录反例的顺序，尚未经过效果验证。','skill_id':'content-understanding'},
            {'label':'试访验证适用条件','reason':'结合访谈组织方法做一次小样本试访，再决定如何迁移。','skill_id':'reference-transfer'}]},ensure_ascii=False)},ensure_ascii=False).encode()
        self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
def apple(s): return subprocess.check_output(['osascript','-e',s],text=True,timeout=15).strip()
def quote(s): return json.dumps(s,ensure_ascii=False)
server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
window_id = None
try:
    window_id = int(apple(f'tell application "Google Chrome"\nset w to make new window\nset bounds of w to {{980, 60, 1280, 760}}\nset URL of active tab of w to "http://127.0.0.1:{server.server_port}/note"\nreturn id of w\nend tell'))
    time.sleep(0.8)
    js = '''(()=>{const e=document.querySelector('#drag-note');if(!e)return '{}';const r=e.getBoundingClientRect(),z=outerWidth/innerWidth;return JSON.stringify({x:screenX+(r.left+r.width/2)*z,y:screenY+(outerHeight-innerHeight*z)+(r.top+r.height/2)*z});})()'''
    point = json.loads(apple(f'tell application "Google Chrome" to execute active tab of window id {window_id} javascript {quote(js)}'))
    assert point and point['x'] > 1090, point
    with tempfile.TemporaryDirectory(prefix='mouse-companion-browser-body-') as folder:
        env=dict(os.environ,MOUSE_COMPANION_PROJECTS_DIR=folder+'/projects',OPENAI_API_KEY='fixture-only',OPENAI_BASE_URL=f'http://127.0.0.1:{server.server_port}/v1',OPENAI_MODEL='fixture')
        with open('/tmp/mouse-companion-browser-body.log','w') as log:
            process=subprocess.Popen([str(Path('Mouse Companion.app/Contents/MacOS/MouseCompanion').resolve())],env=env,stdout=log,stderr=log)
            try:
                time.sleep(0.9)
                apple(f'tell application "Google Chrome"\nset index of window id {window_id} to 1\nactivate\nend tell')
                subprocess.run(['/tmp/mouse-companion-clipboard-guard','/tmp/mouse-companion-browser-note-ui',str(process.pid),str(point['x']),str(point['y'])],check=True,timeout=65)
                process.wait(timeout=10)
                assert requests, 'No suggestion request'
                docs=[json.loads(p.read_text()) for p in Path(folder+'/projects').rglob('project.json')]
                materials=[m for d in docs for m in d['materials']]
                assert any('BROWSER_NOTE_BODY_SENTINEL' in m['text'] and m.get('image') and m['metadata'].get('textSource')=='browser_note_body' for m in materials)
                print('PASS: live browser DOM -> actual drop -> persisted note body + cover -> actual API request -> native body preview')
            finally:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=3)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
finally:
    if window_id is not None:
        try: apple(f'tell application "Google Chrome" to close window id {window_id}')
        except Exception: pass
    server.shutdown()

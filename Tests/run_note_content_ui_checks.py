"""Assert actual native suggestion requests contain body text and honest evidence scope."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

requests = []
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_POST(self):
        assert self.headers['Authorization'] == 'Bearer fixture-only'
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        content = body['input'][0]['content'] if isinstance(body['input'], list) else []
        text = content[0]['text'] if content else body['input']
        value = json.loads(text)
        material = value['material']
        assert value['allowed_skills'] == ['content-understanding', 'reference-transfer']
        assert value['analysis_focus'] == 'content_and_project_relevance'
        requests.append((material, len(content)))
        if len(requests) == 1:
            assert material['note_body_available'] and 'NOTE_BODY_SENTINEL' in material['text'] and len(content) == 2
            code, result = 400, {'error': {'message': 'This model does not support input_image'}}
        elif material['note_body_available']:
            assert 'NOTE_BODY_SENTINEL' in material['text'] and material['text_source'] == 'browser_note_body'
            assert not content, 'Text-only fallback should preserve the actual body'
            code, result = 200, {'output_text': json.dumps({'suggestions': [
                {'label': '提取三步访谈结构', 'reason': '正文明确写了试用、追问和收集反例，不是配色教程。', 'skill_id': 'content-understanding'},
                {'label': '比较先试用后追问', 'reason': '结合组织访谈的想法做小样本试访，经验尚未经过效果对照。', 'skill_id': 'reference-transfer'}
            ]}, ensure_ascii=False)}
        else:
            assert material['text_source'] == 'image_ocr' and '封面 OCR' in material['text']
            assert 'NOTE_BODY_SENTINEL' not in material['text']
            code, result = 200, {'output_text': json.dumps({'suggestions': [
                {'label': '补读笔记正文', 'reason': '未读取正文，仅有封面和 OCR，暂时无法判断具体访谈方法。', 'skill_id': 'content-understanding'},
                {'label': '核对适用的访谈场景', 'reason': '正文缺失，应先补充使用场景再决定怎样迁移。', 'skill_id': 'reference-transfer'}
            ]}, ensure_ascii=False)}
        data = json.dumps(result, ensure_ascii=False).encode()
        self.send_response(code); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
server = HTTPServer(('127.0.0.1',0), Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='mouse-companion-note-body-') as folder:
        directory = folder + '/projects'
        subprocess.run(['/tmp/mouse-companion-note-fixture', directory],check=True)
        env = dict(os.environ,MOUSE_COMPANION_PROJECTS_DIR=directory,OPENAI_API_KEY='fixture-only',OPENAI_BASE_URL=f'http://127.0.0.1:{server.server_port}/v1',OPENAI_MODEL='fixture')
        with open('/tmp/mouse-companion-note-ui.log','w') as log:
            process = subprocess.Popen([str(Path('Mouse Companion.app/Contents/MacOS/MouseCompanion').resolve())],env=env,stdout=log,stderr=log)
            try:
                time.sleep(0.9)
                subprocess.run(['/tmp/mouse-companion-clipboard-guard','/tmp/mouse-companion-note-ui',str(process.pid)],check=True,timeout=65)
                assert process.wait(timeout=10) == 0
                assert len(requests) == 3, requests
            finally:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=3)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
    print('PASS: native persisted body + cover, correct request material, content-first skill routing, image fallback retains body, cover-only limitation')
finally:
    server.shutdown()

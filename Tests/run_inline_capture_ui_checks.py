"""Native UI + request contract test; only synthetic page crops and fake credentials."""
import base64
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

requests = []


def jpeg_size(data):
    stream = io.BytesIO(data)
    assert stream.read(2) == b"\xff\xd8"
    while True:
        value = stream.read(1)
        assert value, "Missing JPEG dimensions"
        if value != b"\xff":
            continue
        marker = stream.read(1)
        while marker == b"\xff":
            marker = stream.read(1)
        if marker in (b"\xd8", b"\xd9"):
            continue
        length = int.from_bytes(stream.read(2), "big")
        if marker[0] in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            stream.read(1)
            height = int.from_bytes(stream.read(2), "big")
            width = int.from_bytes(stream.read(2), "big")
            return width, height
        stream.seek(length - 2, 1)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        assert self.headers.get("Authorization") == "Bearer fixture-only"
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert body["store"] is False
        content = body["input"][0]["content"] if isinstance(body["input"], list) else []
        text = content[0]["text"] if content else body["input"]
        shared = json.loads(text.split("shared_session:\n", 1)[1])
        number = len(requests) + 1
        references = shared["pointed_references"]
        images = [piece for piece in content if piece["type"] == "input_image"]
        assert len(references) == [2, 3, 2, 0][number - 1], (number, len(references))
        assert len(images) == [1, 2, 1, 0][number - 1]
        if number < 4:
            assert any("紫色石榴盒" in ref["text_or_ocr"] for ref in references)
        else:
            assert shared["capture_session_id"] != requests[0]["capture_session_id"]
            assert len(shared["collected_materials"]) == 2
        assert len({ref["id"] for ref in references}) == len(references)
        for image in images:
            width, height = jpeg_size(base64.b64decode(image["image_url"].split(",", 1)[1]))
            assert width < 400 and height < 300, "Whole screen leaked into request"
        if number > 1:
            assert "INLINE_RESPONSE_1" in json.dumps(shared["recent_shared_history"])
        requests.append(shared)
        if number == 1:
            time.sleep(1)  # Let the user keep drawing while the first request is pending.
        answer = json.dumps({"output_text": f"**INLINE_RESPONSE_{number}**\n\n已读取本轮选区。"}, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(answer)))
        self.end_headers()
        self.wfile.write(answer)


def apple(source):
    return subprocess.check_output(["osascript", "-e", source], text=True).strip()


app = Path("Mouse Companion.app/Contents/MacOS/MouseCompanion").resolve()
server = HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
previous = apple('tell application "Google Chrome" to return id of active tab of front window')
tab = None
process = None
try:
    with tempfile.TemporaryDirectory(prefix="mouse-companion-inline-") as folder:
        page = Path(folder, "source.html")
        page.write_text('''<!doctype html><meta charset="utf-8"><title>Inline Capture Fixture</title>
        <style>body{font:20px system-ui;padding:60px;background:white}p{margin:20px 0 40px}.tile{display:inline-block;width:180px;height:120px;margin-right:40px;vertical-align:top;background:#fff;border:1px solid #ddd}svg{width:180px;height:120px}</style>
        <h1>圈画内对话测试</h1><p id="selection">本项目盒子名称是「紫色石榴盒」，先验证再采纳。</p>
        <div class="tile"><svg><rect x="30" y="25" width="90" height="60" fill="#1261ff"/></svg></div>
        <div class="tile"><svg><circle cx="90" cy="60" r="35" fill="#7e40ed"/></svg></div>''', encoding="utf-8")
        tab = apple(f'tell application "Google Chrome"\nset t to make new tab at end of tabs of front window with properties {{URL:"{page.as_uri()}"}}\nset active tab index of front window to count of tabs of front window\nactivate\nreturn id of t\nend tell')
        time.sleep(0.7)
        js = """(()=>{const r=document.createRange();r.selectNodeContents(document.getElementById('selection'));getSelection().removeAllRanges();getSelection().addRange(r);return JSON.stringify([...document.querySelectorAll('.tile')].map(e=>{const b=e.getBoundingClientRect();return {x:screenX+b.x,y:screenY+outerHeight-innerHeight+b.y,w:b.width,h:b.height}}));})()"""
        geometry = apple('tell application "Google Chrome" to execute active tab of front window javascript ' + json.dumps(js))
        geometry_path = Path(folder, "geometry.json")
        geometry_path.write_text(geometry)
        env = dict(os.environ, MOUSE_COMPANION_PROJECTS_DIR=folder + "/projects", OPENAI_API_KEY="fixture-only", OPENAI_BASE_URL=f"http://127.0.0.1:{server.server_port}/v1", OPENAI_MODEL="fixture")
        with open("/tmp/mouse-companion-inline-ui.log", "w") as log:
            process = subprocess.Popen([str(app)], env=env, stdout=log, stderr=log)
            time.sleep(0.7)
            apple('tell application "Google Chrome" to activate')
            subprocess.run(["/tmp/mouse-companion-inline-ui", str(process.pid), str(geometry_path)], check=True, timeout=50)
            assert process.wait(timeout=10) == 0
        assert len(requests) == 4
        manifest = json.loads(Path(folder, "projects/manifest.json").read_text())
        active = next(entry for entry in manifest["entries"] if entry["name"] == manifest["activeProject"])
        state = json.loads(Path(folder, "projects", active["id"], "project.json").read_text())
        assert len(state["assets"]) == 3 and len(state["turns"]) == 8
        assert len(state["materials"]) == 2
        assert {item["note"] for item in state["materials"]} == {"图片备注/保留", "文字备注"}
        assert all(item["metadata"]["sourceURL"].endswith("source.html") for item in state["materials"])
        assert all(turn.get("referenceIDs") for turn in state["turns"] if turn["role"] == "user" and "第四轮" not in turn["text"])
        print("PASS: reopening capture excludes old references/photos; current text/image selections enter the tray with source and notes, duplicate transfer is idempotent, and history preserves the attachments")
finally:
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    if tab:
        apple(f'tell application "Google Chrome"\nclose tab id {tab} of front window\nrepeat with i from 1 to count of tabs of front window\nif id of tab i of front window is {previous} then set active tab index of front window to i\nend repeat\nend tell')
    server.shutdown()

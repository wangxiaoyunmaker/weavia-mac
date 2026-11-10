"""Exercise response sizing and clipboard interactions against a local fixture API."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        assert self.headers.get("Authorization") == "Bearer fixture-only"
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert isinstance(body["input"], str) and body["store"] is False
        prompt = body["input"].split("\n", 1)[0]
        if prompt.endswith("broken"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            value = {"type": "response.output_text.delta", "delta": "这是一段已经生成的内容。"}
            self.wfile.write(("data: " + json.dumps(value, ensure_ascii=False) + "\n\n").encode()); self.wfile.flush()
            time.sleep(0.6)
            return
        if prompt.endswith("stream"):
            assert body["stream"] is True
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.end_headers()
            def event(obj):
                value = ("event: " + obj["type"] + "\r\ndata: " + json.dumps(obj, ensure_ascii=False) + "\r\n\r\n").encode()
                # Deliberately split inside Chinese UTF-8 and SSE lines.
                for start in range(0, len(value), 7):
                    self.wfile.write(value[start:start+7]); self.wfile.flush()
            chunks = ["流式输出。", "\n\n第一段：这段文字正在逐步生成，气泡应随着内容自然伸展。\n\n", "第二段：鼠标可以拖选已经生成的一部分文字，后续输出不会打断当前选区。\n\n", "第三段：生成还在继续，历史只记录完成后的完整回答。\n\n", "最后一行：流式验收"]
            try:
                event({"type": "response.created"})
                for index, chunk in enumerate(chunks):
                    event({"type": "response.output_text.delta", "delta": chunk, "output_index": 0, "content_index": 0})
                    time.sleep(1.6 if index == 0 else 0.8)
                event({"type": "response.completed", "response": {"status": "completed", "output_text": "".join(chunks)}})
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if prompt.endswith("short"):
            answer = "**短答：你好。**"
        elif prompt.endswith("medium"):
            answer = "这是一段会随着字数增长而自然变宽的回答。"
        elif prompt.endswith("long"):
            answer = "# 长回答标题\n\n" + "\n\n".join(f"第 {index} 段：蓝紫色的轮廓帮助识别伙伴，文字随内容伸缩，长文滚动查看。" for index in range(80)) + "\n\n最后一行：复制验收"
        else:
            raise AssertionError(prompt)
        value = json.dumps({"output_text": answer}, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(value)))
        self.end_headers()
        self.wfile.write(value)


def apple(script):
    return subprocess.check_output(["osascript", "-e", script], text=True).strip()


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
fixture = subprocess.Popen(["/tmp/mouse-companion-answer-source"])
try:
    time.sleep(0.5)
    with tempfile.TemporaryDirectory(prefix="mouse-companion-answer-") as folder:
        env = dict(os.environ, MOUSE_COMPANION_PROJECTS_DIR=folder + "/projects", OPENAI_API_KEY="fixture-only", OPENAI_BASE_URL=f"http://127.0.0.1:{server.server_port}/v1", OPENAI_MODEL="fixture")
        with open("/tmp/mouse-companion-answer-ui.log", "w") as log:
            process = subprocess.Popen([str(Path("Mouse Companion.app/Contents/MacOS/MouseCompanion").resolve())], env=env, stdout=log, stderr=log)
            try:
                time.sleep(0.8)
                subprocess.run(["/tmp/mouse-companion-clipboard-guard", "/tmp/mouse-companion-answer-ui", str(process.pid)], check=True, timeout=80)
                assert process.wait(timeout=10) == 0
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    print("PASS: native response sizing, fold/unfold, full and selected-text copying, and project history; clipboard restored by a separate in-memory guard")
finally:
    fixture.terminate()
    fixture.wait(timeout=5)
    server.shutdown()

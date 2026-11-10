"""Local contract fixture; asserts request contents, never handles real credentials."""
import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler


class Handler(BaseHTTPRequestHandler):
    count = 0

    def log_message(self, *_):
        pass

    def do_POST(self):
        assert self.headers.get("Authorization") == "Bearer fixture-only"
        assert self.path == "/v1/responses"
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert body["store"] is False
        Handler.count += 1
        n = Handler.count
        assert bool(body.get("stream")) == (n != 3)
        if n == 1:
            content = body["input"][0]["content"]
            assert content[1]["type"] == "input_image"
            assert content[1]["image_url"].startswith("data:image/jpeg;base64,")
            response, code = {"error": {"message": "This model does not support input_image"}}, 400
        else:
            text = body["input"]
            assert isinstance(text, str) and "input_image" not in text
            if n == 2:
                assert "新手没有发现保存按钮" in text and '"image_sent":false' in text
                answer = "共享回答甲：先验证，再采纳。"
            elif n == 3:
                value = json.loads(text)
                shared = json.loads(value["shared_session"])
                assert "共享回答甲" in value["shared_session"] and "会话约束" in value["shared_session"]
                assert shared["collected_materials"][0]["user_note"] == "已有项目备注"
                assert value["input_mode"] == "text_only"
                answer = json.dumps({"suggestions": [
                    {"label": "补一次首次使用测试", "reason": "这是待验证建议", "skill_id": "evidence-framing"},
                    {"label": "对照保存入口版本", "reason": "结合项目约束先比较", "skill_id": "reference-transfer"}
                ]}, ensure_ascii=False)
            elif n == 4:
                assert "补一次首次使用测试" in text and "tray_suggestions_unaccepted" in text
                assert "先验证，再采纳" in text
                assert '"pointed_references":[]' in text
                answer = "跨界面会话通过"
            else:
                raise AssertionError("Unexpected repeated request")
            response, code = {"output_text": answer}, 200
        if n == 2:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            def emit(obj):
                self.wfile.write(("data: " + json.dumps(obj, ensure_ascii=False) + "\n\n").encode()); self.wfile.flush()
            emit({"type": "response.output_text.delta", "delta": "共享回答甲："})
            time.sleep(0.1)
            emit({"type": "response.output_text.delta", "delta": "先验证，再采纳。"})
            emit({"type": "response.completed", "response": response})
            return
        data = json.dumps(response, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


server = HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()

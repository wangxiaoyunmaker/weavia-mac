"""Exercise real native drag/drop with synthetic content and isolated storage."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

fixture = subprocess.Popen(["/tmp/mouse-companion-folder-source"])
try:
    time.sleep(0.5)
    with tempfile.TemporaryDirectory(prefix="mouse-companion-folder-") as folder:
        env = dict(os.environ, MOUSE_COMPANION_PROJECTS_DIR=folder + "/projects", OPENAI_API_KEY="fixture-only", OPENAI_BASE_URL="http://127.0.0.1:1/v1", OPENAI_MODEL="fixture")
        with open("/tmp/mouse-companion-folder-ui.log", "w") as log:
            process = subprocess.Popen([str(Path("Mouse Companion.app/Contents/MacOS/MouseCompanion").resolve())], env=env, stdout=log, stderr=log)
            try:
                time.sleep(0.9)
                subprocess.run(["/tmp/mouse-companion-clipboard-guard", "/tmp/mouse-companion-folder-ui", str(process.pid), str(fixture.pid)], check=True, timeout=70)
                assert process.wait(timeout=10) == 0
                projects = list(Path(folder + "/projects").rglob("project.json"))
                if not projects:
                    projects = [p for p in Path(folder + "/projects").rglob("*.json") if p.name != "manifest.json" and ".backup" not in p.name]
                data = [json.loads(p.read_text()) for p in projects]
                materials = [m for obj in data for m in obj.get("materials", [])]
                assert any(m.get("note") == "文件夹收起后保留的想法" for m in materials), "Minimized note did not reach project persistence"
                print("PASS: folder collection and minimized note persisted in the isolated project")
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait()
finally:
    fixture.terminate(); fixture.wait(timeout=5)

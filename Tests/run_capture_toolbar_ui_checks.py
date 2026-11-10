"""Check toolbar states in the packaged native app without making API calls."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

fixture = subprocess.Popen(["/tmp/mouse-companion-answer-source"])
try:
    time.sleep(0.5)
    with tempfile.TemporaryDirectory(prefix="mouse-companion-toolbar-") as folder:
        env = dict(os.environ, MOUSE_COMPANION_PROJECTS_DIR=folder + "/projects", OPENAI_API_KEY="fixture-only", OPENAI_BASE_URL="http://127.0.0.1:1/v1", OPENAI_MODEL="fixture")
        with open("/tmp/mouse-companion-toolbar-ui.log", "w") as log:
            process = subprocess.Popen([str(Path("Mouse Companion.app/Contents/MacOS/MouseCompanion").resolve())], env=env, stdout=log, stderr=log)
            try:
                time.sleep(0.9)
                subprocess.run(["/tmp/mouse-companion-clipboard-guard", "/tmp/mouse-companion-toolbar-ui", str(process.pid)], check=True, timeout=60)
                process.wait(timeout=10)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
finally:
    fixture.terminate()
    fixture.wait()

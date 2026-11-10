"""Run against a freshly compiled ProjectPersistenceChecks executable; no live app data."""
import json
import pathlib
import subprocess
import tempfile
import sys

binary = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mouse-companion-persistence-checks"
with tempfile.TemporaryDirectory(prefix="mouse-companion-persistence-") as folder:
    root = pathlib.Path(folder)

    def run(mode):
        subprocess.run([binary, mode, folder], check=True, timeout=40)

    run("write")
    manifest = json.loads((root / "manifest.json").read_text())
    assert {"甲/含路径字符", "乙"}.issubset({entry["name"] for entry in manifest["entries"]})
    # Project names (including slashes) never become filesystem paths.
    assert not (root / "甲").exists()
    run("read")
    run("verify")
    manifest = json.loads((root / "manifest.json").read_text())
    item = next(entry for entry in manifest["entries"] if entry["name"] == "甲/含路径字符")
    document = root / item["id"] / "project.json"
    assert "备份恢复后仍能保存" not in document.read_text()
    document.write_text('{"interrupted":', encoding="utf-8")
    run("recovery")
    assert "备份恢复后仍能保存" in document.read_text()
    # With neither valid primary nor valid backup, refuse to overwrite the originals.
    document.write_text("corrupt original", encoding="utf-8")
    document.with_suffix(".json.backup").write_text("corrupt backup", encoding="utf-8")
    before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    run("blocked")
    after = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    assert before == after
    blocker = root / "blocked-root"
    blocker.write_text("regular file blocks directory creation", encoding="utf-8")
    subprocess.run([binary, "writeFailure", str(blocker)], check=True, timeout=40)
    print("PASS: separate-process relaunch, complete project round-trip, continued chat, project isolation, removal, backup recovery and no overwrite on corruption")

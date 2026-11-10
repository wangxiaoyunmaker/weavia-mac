"""Read-only source regression: retain the working native capture implementation.

This does not launch either app, read keys, capture the screen, or call a model.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
original = next(parent / "mouse-companion-native-prototype" for parent in root.parents if (parent / "mouse-companion-native-prototype/Sources/MouseCompanion").is_dir())
source = root / "Sources/MouseCompanion"
baseline = original / "Sources/MouseCompanion"

for filename in (
    "DesignOCR.swift", "BrowserCapture.js",
    "BrowserCaptureRequest.swift", "BrowserTextSource.swift",
    "BrowserDragPayload.swift", "CapturePreviewRequest.swift",
    "AgentTransport.swift", "AgentStreaming.swift",
):
    assert (source / filename).read_bytes() == (baseline / filename).read_bytes(), filename

# Smart tagging is additive; legacy Agent methods remain byte-identical.
agent = (source / "CompanionAgent.swift").read_text()
a = agent.index('    // Smart tags use exactly one confirmed card')
b = agent.index('    @discardableResult func send(', a)
assert agent[:a] + agent[b:] == (baseline / "CompanionAgent.swift").read_text()

# New Stop action only extends the measured header action count; the default layout is unchanged.
layout = (source / "AnswerBubbleLayout.swift").read_text()
layout = layout.replace(', actionCount: Int = 4', '')
layout = layout.replace(' + CGFloat(max(0, actionCount - 4)) * 26', '')
layout = layout.replace('// Four standard actions plus Stop while generating; long status text may truncate.', '// A compact status and four 24pt actions; long status text may truncate on a small display.')
assert layout == (baseline / "AnswerBubbleLayout.swift").read_text()

# Only improve the original toolbar's failure text; capture mechanics stay identical.
capture = (source / "ContextCapture.swift").read_text()
original_capture = (baseline / "ContextCapture.swift").read_text()
helper = capture.split('    private var unavailableSnapshotMessage: String {', 1)[1].split('    private func selectTool', 1)[0]
assert 'guard #available(macOS 14.0, *)' in helper
assert 'guard CGPreflightScreenCaptureAccess()' in helper
assert '屏幕与系统音频录制中允许 WEAVIA' in helper
assert '已允许屏幕录制，但系统暂未返回截图' in helper
normalized_capture = re.sub(r'    private var unavailableSnapshotMessage: String \{.*?(?=    private func selectTool)', '', capture, flags=re.S)
normalized_capture = normalized_capture.replace('view?.snapshot == nil ? unavailableSnapshotMessage : nil', 'view?.snapshot == nil ? "暂时无法截屏；圈画需要屏幕录制权限（macOS 14+）。" : nil')
assert normalized_capture == original_capture

current = (source / "main.swift").read_text()
old = (baseline / "main.swift").read_text()
def section(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]

# Original collection and freeform conversation paths are reused, not reimplemented.
native_run = section(current, "    private func runAgent(prompt: String)", "private final class AppDelegate")
# Explicit lifecycle guards are the only additions to the native conversation path.
native_run = native_run.replace('        agentBusy = true\n', '')
native_run = native_run.replace('        conversationGeneration = UUID(); agentRequest?.cancel(); retireCanvasAgent(status: "cancelled")', '        agentRequest?.cancel()')
native_run = native_run.replace('guard let visible = screen?.visibleFrame else { agentBusy = false; return }', 'guard let visible = screen?.visibleFrame else { return }')
native_run = native_run.replace('guard attempts < 100 else { agentBusy = false;', 'guard attempts < 100 else {')
native_run = native_run.replace('            self.agentBusy = false; self.agentRequest = nil\n', '')
# Pointer editing now also resets the preserved input idle timer.
native_run = native_run.replace('            self?.userPrompt.notePointerActivity(event)\n', '')
native_run = native_run.replace('self?.userPrompt.notePointerActivity(event); self?.userPrompt.follow', 'self?.userPrompt.follow')
assert native_run == section(old, "    private func runAgent(prompt: String)", "private final class AppDelegate")
assert 'as? Bool ?? true' in current
assert re.search(r'if UserDefaults.standard.object\(forKey: "weavia.inspirationModeEnabled"\).*?inspiration.activate\(\).*?registerSlashHotKeyIfNeeded\(\)', current, re.S)
assert 'UserDefaults.standard.set(active, forKey: "weavia.inspirationModeEnabled")' in current
assert 'UserDefaults.standard.set(!inspiration.isActive, forKey: "weavia.inspirationModeEnabled")' in current
activate = section(current, '    func activate() {', '    func deactivate() {')
assert 'installMonitors()' in activate and 'onModeChanged?()' in activate
deactivate = section(current, '    func deactivate() {', '    func showCanvas()')
assert 'canvasDraftCards = nil' in deactivate and 'onModeChanged?()' in deactivate
print('PASS: unchanged transport/capture dependencies; audited Stop header and request-lifecycle additions; original native runAgent/event-monitor behavior; startup and explicit mode preference wiring.')

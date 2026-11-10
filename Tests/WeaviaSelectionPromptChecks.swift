// Appended to an isolated test copy. All windows remain unordered; no app/store entry runs.
private extension UserPromptController {
    func fixtureRun() {
        precondition(idleDelay == 5 && fadeDuration == 3)
        let first = NSPoint(x: 400, y: 400)
        showForSelection(at: first)
        precondition(selectionAnchored && !followsCursor && !panel.isVisible)
        input.stringValue = "Synthetic unsent draft 中文"
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        let timer = idleTimer
        follow(cursor: NSPoint(x: 900, y: 900))
        precondition(anchor == first, "Canvas input must not chase the system pointer")
        repositionSelection(at: NSPoint(x: 420, y: 380))
        precondition(idleTimer === timer && draft == "Synthetic unsent draft 中文", "Geometry preserves timer/editor/draft")
        RunLoop.current.run(until: Date().addingTimeInterval(5.3))
        precondition(panel.alphaValue < 1 && panel.alphaValue > 0, "Five seconds idle begins three-second fade")
        RunLoop.current.run(until: Date().addingTimeInterval(3.0))
        precondition(panel.alphaValue < 0.01 && draft == "Synthetic unsent draft 中文")
        precondition(panel.ignoresMouseEvents && !panel.isVisible)
        showForSelection(at: first)
        precondition(draft == "Synthetic unsent draft 中文" && panel.alphaValue == 1)
        hideSelection()
        precondition(idleTimer == nil && fadeTimer == nil && draft == "Synthetic unsent draft 中文")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(!panel.isVisible, "Dismissal cannot reopen an obsolete prompt")
        input.isEditable = false // Submitted text is not a new unsent draft.
        showForSelection(at: first)
        precondition(draft.isEmpty)
        reset(); precondition(draft.isEmpty && !selectionAnchored && idleTimer == nil && fadeTimer == nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
private let prompt = UserPromptController()
prompt.fixtureRun()
let geometry: [String: Any] = ["x": 100, "y": 50, "width": 400, "height": 200, "viewportWidth": 1000, "viewportHeight": 800]
let rect = MacWorkspaceCanvas.viewportRect(geometry, in: NSRect(x: 20, y: 30, width: 1500, height: 1200))!
precondition(rect == NSRect(x: 170, y: 105, width: 600, height: 300))
var invalid = geometry; invalid["width"] = -1; precondition(MacWorkspaceCanvas.viewportRect(invalid, in: .zero) == nil)
invalid = geometry; invalid["x"] = Double.nan; precondition(MacWorkspaceCanvas.viewportRect(invalid, in: .zero) == nil)
invalid = geometry; invalid["viewportWidth"] = 0; precondition(MacWorkspaceCanvas.viewportRect(invalid, in: .zero) == nil)
invalid = geometry; invalid["x"] = 900; precondition(MacWorkspaceCanvas.viewportRect(invalid, in: .zero) == nil)
print("PASS: original prompt 5s idle + 3s fade, draft restoration, stationary selection anchor, geometry does not reset timer, dismissal cancellation, submitted-text clearing, viewport scaling and invalid bounds; all offscreen")

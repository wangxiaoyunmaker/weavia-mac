// Appended only to a temporary test copy of main.swift. No real app entry or store runs.
private extension AgentAnswerController {
    func fixtureCheckWorking() {
        precondition(!stopButton.isHidden && stopButton.isEnabled)
        precondition(!panel.isVisible && latestText.isEmpty)
        panel.contentView?.layoutSubtreeIfNeeded()
        for button in [historyButton, copyButton, stopButton, collapseButton, closeButton] {
            let frame = button.convert(button.bounds, to: panel.contentView)
            precondition(frame.width > 0 && frame.width <= 26 && frame.height > 0 && frame.height <= 36)
            precondition(panel.contentView!.bounds.insetBy(dx: -1, dy: -1).contains(frame), "Header actions must fit")
        }
    }
    func fixtureStop() { stopButton.performClick(nil) }
    func fixtureCheckStopped(_ expected: String) {
        precondition(stopButton.isHidden && !stopButton.isEnabled)
        precondition(status.stringValue.hasPrefix("已停止"))
        precondition(latestText == expected && copyButton.isEnabled)
        precondition(!panel.isVisible)
    }
    func fixtureCheckAnswer(_ expected: String, completed: Bool) {
        precondition(stopButton.isHidden)
        precondition(latestText == expected && copyButton.isEnabled)
        precondition(answer.string.contains("END_MARKER"))
        precondition(!answer.string.contains("**"), "Markdown must render as rich text")
        precondition(answer.frame.height > answerScroll.contentSize.height, "Long answer must scroll")
        precondition(panel.frame.width <= 420 && panel.frame.height <= 360)
        if completed { precondition(status.stringValue == "已完成") }
        precondition(!panel.isVisible)
    }
    func fixtureCheckHidden() { precondition(!panel.isVisible) }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
private let bubble = AgentAnswerController()
var stops = 0
bubble.onStop = { stops += 1 }
let anchor = NSRect(x: 700, y: 600, width: 44, height: 44)
let text = "**Synthetic heading**\n\n" + String(repeating: "- Long synthetic content, entirely local.\n", count: 90) + "\nEND_MARKER"
bubble.showWorking(belowLeftOf: anchor)
bubble.fixtureCheckWorking()
bubble.showPartial(text)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
bubble.fixtureStop()
bubble.fixtureCheckStopped(text)
precondition(stops == 1)
bubble.fixtureStop(); precondition(stops == 1, "Stopped request cannot cancel twice")
bubble.showWorking(belowLeftOf: anchor)
bubble.fixtureCheckWorking()
bubble.showPartial(text)
bubble.showAnswer(text, belowLeftOf: anchor)
bubble.fixtureCheckAnswer(text, completed: true)
bubble.fixtureStop(); precondition(stops == 1, "Completed request has no active stop")
bubble.hide()
bubble.showPartial(text + "\nlate synthetic text")
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
bubble.fixtureCheckHidden()
bubble.showWorking(belowLeftOf: anchor)
bubble.fixtureCheckWorking()
bubble.showPartial(text)
bubble.showFailure("Synthetic failure")
bubble.fixtureCheckAnswer(text + "\n\n---\n\n生成中断：Synthetic failure", completed: false)
print("PASS: offscreen native bubble Stop/retry/completion/failure, full long rich-text/scroll layout, duplicate-stop prevention and no reopen after Close")

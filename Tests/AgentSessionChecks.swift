import AppKit

@main struct AgentSessionChecks {
    static func main() {
        precondition(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] == "fixture-only", "Run only with the local fixture; do not read real credentials")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mouse-companion-session-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agent = AgentAPIService(context: CompanionContext(store: CompanionProjectStore(directory: directory)))
        let image = NSImage(size: NSSize(width: 80, height: 80), flipped: true) { _ in NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 80, height: 80).fill(); return true }
        agent.context.setProject("会话测试", area: "研究")
        agent.context.beginCaptureSession()
        agent.context.add(CompanionContextAsset(title: "圈选", text: "圈选原文：新手没有发现保存按钮", image: image, sourceApp: "Fixture", sourceURL: nil, kind: "selected_region"))
        agent.context.upsert(CompanionMaterial(id: "fixture-material", project: "会话测试", title: "素材甲", text: "访谈原文", note: "已有项目备注", area: "研究", image: nil, saved: true))
        func wait(_ run: (@escaping () -> Void) -> Void) {
            var done = false; run { done = true }
            let deadline = Date().addingTimeInterval(8)
            while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            precondition(done, "Fixture timed out")
        }
        var partials: [String] = []
        wait { finish in agent.send("会话约束：先验证，再采纳", onPartial: { partials.append($0) }) { result in
            guard case .success(let value) = result, value.contains("共享回答甲"), value.contains("未接收圈选图片") else { fatalError("Fallback failed: \(result)") }; finish()
        } }
        precondition(partials.count >= 2 && partials[0].contains("共享回答甲") && !partials[0].contains("先验证，再采纳"))
        precondition(partials.allSatisfy { $0.contains("未接收圈选图片") })
        precondition(agent.context.turns.filter { $0.role == "assistant" }.count == 1, "Each stream delta was stored as a separate answer")
        let input = DesignSuggestionContext(title: "素材甲", text: "访谈原文", kind: "文字卡片", note: "", project: "会话测试", location: "研究", memory: [])
        wait { finish in _ = agent.suggest(input) { result in
            guard case .success(let suggestions) = result, suggestions.count == 2 else { fatalError("Suggestion failed: \(result)") }; finish()
        } }
        precondition(agent.context.flush() == nil)
        let resumed = AgentAPIService(context: CompanionContext(store: CompanionProjectStore(directory: directory)))
        precondition(resumed.context.project == "会话测试")
        wait { finish in resumed.send("接着托盘的建议继续") { result in
            guard case .success(let value) = result, value.contains("跨界面会话通过") else { fatalError("Continuity failed: \(result)") }; finish()
        } }
        precondition(resumed.context.turns.filter { $0.purpose == "tray_suggestions_unaccepted" }.count == 1)
        precondition(resumed.context.flush() == nil)
        print("PASS: actual shared agent requests / image rejection fallback / restored tray and chat continuity after agent recreation")
    }
}

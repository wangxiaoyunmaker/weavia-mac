import AppKit

@main struct ProjectPersistenceChecks {
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        precondition(directory.path.hasPrefix(NSTemporaryDirectory()) || directory.path.hasPrefix("/tmp/"), "Use an isolated fixture directory")
        let store = CompanionProjectStore(directory: directory)
        let context = CompanionContext(store: store)
        if mode == "write" {
            let image = NSImage(size: NSSize(width: 120, height: 80), flipped: true) { _ in
                NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 120, height: 80).fill()
                NSColor.yellow.setFill(); NSRect(x: 20, y: 20, width: 30, height: 30).fill(); return true
            }
            context.setProject("甲/含路径字符", area: "色彩区")
            context.add(CompanionContextAsset(title: "圈画与原文", text: "请保留这段圈选文字", image: image, sourceApp: "Test Browser", sourceURL: "https://example.com/source?q=kept", kind: "selected_region"))
            var metadata = CompanionMaterial.Metadata()
            metadata.source = "Test Browser"; metadata.kind = "网页卡片"
            metadata.sourceURL = "https://example.com/post?login-context=kept"
            metadata.originalImageURL = "https://example.com/original.png"
            metadata.browserBundleID = "com.google.Chrome"; metadata.renderedPreview = true
            metadata.acceptedSuggestions = ["对照原型"]
            metadata.generatedSuggestions = [DesignSuggestion(label: "对照原型", reason: "保留采纳依据", skillID: "reference-transfer")]
            metadata.suggestionEvidence = metadata.generatedSuggestions
            for i in 0..<30 {
                context.upsert(CompanionMaterial(id: UUID().uuidString, project: context.project, title: "素材 \(i)", text: i == 0 ? "较早材料中的榴莲约束" : "完整原文 \(i)", note: "个人想法 \(i)", area: context.area, image: i == 29 ? image : nil, saved: i != 29, metadata: metadata))
            }
            context.record(role: "user", text: String(repeating: "长文字", count: 4000) + "榴莲约束：先验证再采纳", purpose: "conversation")
            for i in 0..<40 { context.record(role: i % 2 == 0 ? "user" : "assistant", text: "完整对话 \(i)", purpose: "conversation") }
            context.record(role: "assistant", text: "这是一条尚未采纳的托盘建议", purpose: "tray_suggestions_unaccepted")
            context.setProject("乙", area: "独立研究区")
            context.add(CompanionContextAsset(title: "项目乙选区", text: "只有乙能读取", image: nil, sourceApp: "Test", sourceURL: nil, kind: "selected_text"))
            context.record(role: "user", text: "乙的独立对话", purpose: "conversation")
            precondition(context.flush() == nil)
            print("WRITE: two projects, PNG, 30 materials, full long transcript, pending tray and accepted suggestions")
        } else if mode == "read" {
            precondition(context.project == "乙" && context.area == "独立研究区")
            precondition(context.currentAssets.isEmpty && context.projectAssets.count == 1 && context.projectAssets[0].text == "只有乙能读取")
            precondition(context.imageInputs().isEmpty)
            precondition(!context.modelContext().contains("榴莲"))
            context.selectProject("甲/含路径字符")
            precondition(context.area == "色彩区")
            precondition(context.materials.filter { $0.project == context.project }.count == 30, "Older materials were discarded")
            let turns = context.turns.filter { $0.project == context.project }
            precondition(turns.count == 42 && turns[0].text.count > 8000, "Full transcript was truncated")
            precondition(turns.last!.purpose == "tray_suggestions_unaccepted")
            precondition(context.projectAssets.first!.sourceURL == "https://example.com/source?q=kept")
            let image = context.projectAssets.first!.image!
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            let colour = rep.colorAt(x: 5, y: 5)!.usingColorSpace(.deviceRGB)!
            precondition(colour.blueComponent > 0.9 && colour.redComponent < 0.1)
            let pending = context.materials.last { $0.project == context.project && !$0.saved }!
            precondition(pending.image != nil && pending.note == "个人想法 29")
            precondition(pending.metadata.sourceURL!.contains("login-context=kept"))
            precondition(pending.metadata.generatedSuggestions.count == 1 && pending.metadata.acceptedSuggestions == ["对照原型"])
            precondition(pending.metadata.browserBundleID == "com.google.Chrome")
            let lookup = context.modelContext(query: "榴莲约束")
            precondition(lookup.contains("榴莲约束：先验证再采纳") && lookup.contains("较早材料中的榴莲约束"), "Older context not found after relaunch")
            context.clearAssets()
            context.record(role: "user", text: "重启后继续聊的这一句", purpose: "conversation")
            precondition(context.flush() == nil)
            print("READ: independent process restored images, sources, notes, project, full history and older context; continued the conversation")
        } else if mode == "verify" {
            precondition(context.project == "甲/含路径字符")
            precondition(context.currentAssets.isEmpty, "Deleted selections returned after restart")
            precondition(context.turns.last { $0.project == context.project }!.text == "重启后继续聊的这一句")
            precondition(context.materials.filter { $0.project == context.project }.count == 30)
            context.selectProject("乙"); precondition(context.projectAssets.count == 1 && context.currentAssets.isEmpty)
            print("VERIFY: project choice, removal, continued conversation and other project survive a second relaunch")
        } else if mode == "recovery" {
            precondition(context.storageStatus.contains("备份"))
            precondition(!context.materials.isEmpty)
            context.record(role: "user", text: "备份恢复后仍能保存", purpose: "conversation")
            precondition(context.flush() == nil)
            print("RECOVERY: interrupted/corrupt JSON recovered from previous atomic backup")
        } else if mode == "writeFailure" {
            let image = NSImage(size: NSSize(width: 40, height: 40), flipped: true) { _ in NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 40, height: 40).fill(); return true }
            context.add(CompanionContextAsset(title: "失败后重试的图", text: "保留原文", image: image, sourceApp: "Test", sourceURL: nil, kind: "selected_region"))
            precondition(context.flush() != nil, "I/O failure was reported as a successful save")
            try FileManager.default.removeItem(at: directory)
            precondition(context.flush() == nil, "Retry did not clear the I/O error")
            let restored = CompanionContext(store: CompanionProjectStore(directory: directory))
            precondition(restored.projectAssets.first?.image != nil, "Image cache lost the pending PNG after a failed write")
            print("WRITE RETRY: failed save is visible, and retry preserves the image before committing JSON")
        } else if mode == "blocked" {
            precondition(context.storageStatus.contains("暂停"))
            context.record(role: "user", text: "不得覆盖损坏的原文件", purpose: "conversation")
            precondition(context.flush() != nil)
            print("BLOCKED: unreadable project stays intact and reports the failed save")
        }
    }
}

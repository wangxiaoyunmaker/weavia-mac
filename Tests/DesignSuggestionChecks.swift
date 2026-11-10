import Foundation

@main
struct DesignSuggestionChecks {
    static func main() throws {
        let context = DesignSuggestionContext(title: "访谈摘录", text: "参与者在第一次使用时没有发现保存按钮。", kind: "文字卡片", note: "用于海报工具的新手引导", project: "海报工具", location: "研究摘录", memory: [])
        precondition(context.skills.map(\.id) == ["evidence-framing", "reference-transfer"])
        precondition(DesignSkillCatalog.selected(for: "排版层级").map(\.id) == ["visual-hierarchy", "reference-transfer"])
        let json = """
        {"suggestions":[{"label":"记录首次使用的触发条件","reason":"原文仅描述初次使用，不能推广为所有用户都找不到按钮。","skill_id":"evidence-framing"},{"label":"试做保存入口的引导版本","reason":"将摘录转成一个待测试的入口提示方案，比较首次使用表现。","skill_id":"reference-transfer"}]}
        """
        let parsed = try context.parse(json)
        precondition(parsed.count == 2)
        do { _ = try context.parse(json.replacingOccurrences(of: "evidence-framing", with: "invented-theory")); fatalError("Unknown skill accepted") } catch {}
        do { _ = try context.parse("no JSON"); fatalError("Invalid result accepted") } catch {}
        let data = context.input.data(using: .utf8)!
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition((object["project_memory"] as? [[String: String]])?.isEmpty == true)
        precondition(object["input_mode"] as? String == "text_only")
        var page = DesignSuggestionContext(title: "访谈方法笔记", text: "先试用，再追问原因，最后收集反例。", kind: "网页卡片", note: "借鉴组织访谈的方法", project: "海报工具", location: "标题排版探索区", memory: [])
        page.textSource = "browser_note_body"; page.imageDataURLs = ["attached"]
        precondition(page.skills.map(\.id) == ["content-understanding", "reference-transfer"], "A cover or project area must not force visual analysis")
        let payload = try JSONSerialization.jsonObject(with: Data(page.input.utf8)) as! [String: Any]
        precondition((payload["material"] as! [String: Any])["note_body_available"] as? Bool == true)
        var cover = DesignSuggestionContext(title: "封面", text: "封面OCR", kind: "网页卡片", note: "", project: "海报工具", location: "排版", memory: [])
        cover.textSource = "image_ocr"; cover.imageDataURLs = ["attached"]
        precondition(cover.skills.map(\.id) == ["content-understanding", "reference-transfer"] && !cover.hasNoteBody)
        precondition(cover.instructions.contains("未读取正文"))
        let visual = DesignSuggestionContext(title: "笔记", text: "内容", kind: "网页卡片", note: "分析配色和排版", project: "海报工具", location: "研究", memory: [])
        precondition(visual.skills.first?.id == "visual-hierarchy")
        precondition(DesignSkillCatalog.selected(for: "总结图片里的笔记内容", visualInput: true).first?.id == "content-understanding")
        var changed = page; changed.textSource = "image_ocr"
        precondition(changed.fingerprint != page.fingerprint)
        print("Design skills, input boundary and result validation: PASS")
    }
}

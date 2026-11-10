import AppKit

@main struct NoteContentFixture {
    static func main() {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let context = CompanionContext(store: CompanionProjectStore(directory: folder))
        context.setProject("正文理解验收", area: "标题排版探索区")
        let image = NSImage(size: NSSize(width: 100, height: 80), flipped: true) { _ in NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 100, height: 80).fill(); return true }
        var bodyMeta = CompanionMaterial.Metadata()
        bodyMeta.kind = "网页卡片"; bodyMeta.source = "Google Chrome · fixture.invalid"
        bodyMeta.sourceURL = "https://fixture.invalid/note/body"; bodyMeta.textSource = "browser_note_body"; bodyMeta.textTruncated = false; bodyMeta.fromBrowserPage = true
        context.upsert(CompanionMaterial(id: "11111111-1111-4111-8111-111111111111", project: context.project, title: "访谈方法笔记", text: "NOTE_BODY_SENTINEL：先让参与者试用工具，再追问行为原因，最后整理与预期不同的反例。这是访谈组织经验，尚未做效果对照，不是视觉排版教程。", note: "想借鉴组织访谈的方法", area: context.area, image: image, saved: false, metadata: bodyMeta))
        var coverMeta = CompanionMaterial.Metadata()
        coverMeta.kind = "网页卡片"; coverMeta.source = "Google Chrome · fixture.invalid"; coverMeta.sourceURL = "https://fixture.invalid/note/cover"
        // Legacy material: image + OCR, without the new optional provenance keys.
        context.upsert(CompanionMaterial(id: "22222222-2222-4222-8222-222222222222", project: context.project, title: "只有封面的旧素材", text: "封面 OCR：访谈技巧合集", note: "", area: context.area, image: image, saved: false, metadata: coverMeta))
        precondition(context.flush() == nil)
        let loaded = CompanionContext(store: CompanionProjectStore(directory: folder))
        let body = loaded.materials.first { $0.id.hasPrefix("11111111") }!
        precondition(body.image != nil && body.text.contains("NOTE_BODY_SENTINEL") && body.metadata.textSource == "browser_note_body")
        print("PASS: body + image + provenance persisted together; legacy OCR material remains readable")
    }
}

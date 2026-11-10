// Appended to a temporary copy of main.swift with the real app entry removed.
// No application window is ordered, no clipboard or user store is opened.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
let sampleImage = NSImage(size: NSSize(width: 320, height: 220))
sampleImage.lockFocus(); NSColor.systemTeal.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 220)).fill(); NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 90, y: 45, width: 130, height: 130)).fill(); sampleImage.unlockFocus()
let long = String(repeating: "设计素材完整原文，不应因卡片摘要而修改。", count: 30)
var materials = [
    CompanionMaterial(id: "text", project: "研究项目", title: "短文字卡片", text: "先收集，再整理。", note: "", area: "灵感", image: nil, saved: false),
    CompanionMaterial(id: "image", project: "研究项目", title: "图片素材", text: "保留原图与来源", note: "这张图的布局值得参考。", area: "视觉参考", image: sampleImage, saved: false),
    CompanionMaterial(id: "long", project: "研究项目", title: String(repeating: "很长的标题用于验证两行截断", count: 8), text: long, note: String(repeating: "我的批注与原文分开。", count: 20), area: "研究", image: nil, saved: true),
    CompanionMaterial(id: "note", project: "研究项目", title: "只有批注的素材", text: "", note: "补充思路", area: "整理", image: nil, saved: false)
]
materials[0].metadata.source = "合成来源 · 仅测试"
materials[0].metadata.generatedSuggestions = [DesignSuggestion(label: "参考布局", reason: "合成建议", skillID: "visual-hierarchy")]
materials[0].metadata.acceptedSuggestions = ["参考布局"]
private let surface = FlippedView(frame: NSRect(x: 0, y: 0, width: 430, height: 880))
rounded(surface, color: NSColor(hex: 0xF7F8FA), radius: 14)
var bottoms: [CGFloat] = [16,16]
var opened = 0
for material in materials {
    let card = TrayMaterialRow(material) { opened += 1 }
    let column = bottoms[0] <= bottoms[1] ? 0 : 1
    card.frame.origin = NSPoint(x: 16 + CGFloat(column) * 199, y: bottoms[column]); bottoms[column] += card.cardHeight + 10
    surface.addSubview(card)
    check(card.frame.width == 187, "Card width matches Harmony columns")
    check(card.cardHeight > 88, "Cards are not compact rows")
    check(card.subviews.allSatisfy { card.bounds.insetBy(dx: -1, dy: -1).contains($0.frame) }, "Card children must fit")
    let fields = card.subviews.compactMap { $0 as? NSTextField }
    check(fields.contains { $0.stringValue == material.title }, "Title preserved")
    if !material.text.isEmpty { check(fields.contains { $0.stringValue == material.text }, "Full text retained in field; truncation is presentation only") }
    if material.id == "text" {
        check(fields.contains { $0.stringValue == "AI 建议 1 · 已采纳 1" }, "Stored AI/adoption counts visible")
        check(fields.contains { $0.stringValue == "合成来源 · 仅测试" }, "Source provenance retained")
    }
    check(card.accessibilityPerformPress(), "Card can open via accessibility")
}
check(opened == 4, "Every card opens existing detail callback")
check(materials[2].text == long, "No source material mutation")
check(bottoms[0] != bottoms[1], "Masonry supports different card heights")
let imagePath = CommandLine.arguments[1]
if let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) {
    surface.cacheDisplay(in: surface.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: imagePath))
} else { preconditionFailure("Offscreen render unavailable") }
print("PASS: synthetic image/text/note/long-title cards, bounded child frames, full original text, varying heights and detail callback; offscreen render only")

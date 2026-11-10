import AppKit

@main struct InlineCaptureChecks {
    static func main() throws {
        let context = CompanionContext()
        let source = ContextSource(name: "Fixture", bundleID: nil, pid: 0)
        let batch = ContextCaptureBatch(context: context, source: source)
        let image = NSImage(size: NSSize(width: 220, height: 220), flipped: true) { _ in
            NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 220, height: 220).fill(); return true
        }
        let one = ContextStroke(tool: .rectangle, points: [NSPoint(x: 20, y: 20), NSPoint(x: 70, y: 70)])
        let two = ContextStroke(tool: .lasso, points: [NSPoint(x: 100, y: 100), NSPoint(x: 180, y: 100), NSPoint(x: 150, y: 180)])
        let first = try batch.confirm(strokes: [one], image: image, text: "选中文字", includeText: true, sourceURL: "https://example.com")
        precondition(first == 2)
        let firstIDs = Set(context.currentAssets.map(\.id))
        let repeated = try batch.confirm(strokes: [one], image: image, text: "选中文字", includeText: true, sourceURL: nil)
        precondition(repeated == 0)
        precondition(Set(context.currentAssets.map(\.id)) == firstIDs, "Repeated message duplicated a confirmed region")
        let snapshot = context.requestSnapshot()
        let next = try batch.confirm(strokes: [one, two], image: image, text: "选中文字", includeText: true, sourceURL: nil)
        precondition(next == 1)
        precondition(context.currentAssets.count == 3 && snapshot.currentAssets.count == 2, "Later drawing changed an earlier message")
        context.completeOCR(batch.strokeAssets[one.id]!, text: "图一的文字")
        snapshot.refreshPendingOCR(from: context)
        precondition(!snapshot.isPreparing, "An unsent later region blocked the original message")
        precondition(snapshot.currentAssets.contains { $0.text == "图一的文字" })
        batch.reconcileUndo(strokes: [one])
        precondition(context.currentAssets.count == 2 && batch.confirmedStrokeIDs == [one.id])
        context.remove(batch.strokeAssets[one.id]!)
        let removed = batch.removedReferences()
        precondition(removed.strokes == [one.id], "Removing a reference did not remove its visible confirmed outline")

        let full = CompanionContext()
        let blocked = ContextCaptureBatch(context: full, source: source)
        for i in 0..<8 { full.add(CompanionContextAsset(title: "\(i)", text: "\(i)", image: nil, sourceApp: "Fixture", sourceURL: nil, kind: "text")) }
        do {
            _ = try blocked.confirm(strokes: [one], image: image, text: "不应部分加入", includeText: true, sourceURL: nil)
            fatalError("Capacity failure accepted")
        } catch { precondition(full.currentAssets.count == 8 && !full.currentAssets.contains { $0.text == "不应部分加入" }) }
        context.selectProject("另一个项目")
        do { _ = try batch.confirm(strokes: [one], image: image, text: "旧项目", includeText: true, sourceURL: nil); fatalError("Cross-project session accepted") }
        catch { precondition(context.currentAssets.isEmpty) }
        print("PASS: repeated in-mode sends, incremental regions, frozen request context, OCR isolation, undo/removal, atomic capacity validation and project isolation")
    }
}

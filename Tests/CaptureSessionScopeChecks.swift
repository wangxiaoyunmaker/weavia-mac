import AppKit

@main struct CaptureSessionScopeChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mouse-companion-scope-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = CompanionContext(store: CompanionProjectStore(directory: directory))
        let source = ContextSource(name: "Google Chrome", bundleID: "com.google.Chrome", pid: 0)
        let image = NSImage(size: NSSize(width: 300, height: 200), flipped: true) { _ in NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 300, height: 200).fill(); return true }
        let one = ContextStroke(tool: .rectangle, points: [NSPoint(x: 10, y: 10), NSPoint(x: 70, y: 70)])
        let first = ContextCaptureBatch(context: context, source: source)
        _ = try first.confirm(strokes: [one], image: image, text: "HISTORICAL_TEXT", includeText: true, sourceURL: "https://example.com/original")
        let oldIDs = context.currentAssets.map(\.id)
        context.record(role: "user", text: "第一轮讨论", purpose: "conversation", referenceIDs: oldIDs)
        let imported = context.collectCurrentReferences(oldIDs)
        precondition(imported.count == 2 && imported.contains { $0.image != nil } && imported.contains { $0.text == "HISTORICAL_TEXT" })
        precondition(imported.allSatisfy { $0.metadata.sourceURL == "https://example.com/original" && $0.metadata.browserBundleID == "com.google.Chrome" })
        let picture = imported.first { $0.image != nil }!
        context.upsert(CompanionMaterial(id: picture.id, project: picture.project, title: picture.title, text: picture.text, note: "保留我的备注", area: picture.area, image: picture.image, saved: false, metadata: picture.metadata))
        let again = context.collectCurrentReferences(oldIDs)
        precondition(context.materials.count == 2 && again.contains { $0.note == "保留我的备注" })
        first.finish()
        precondition(context.currentAssets.isEmpty && context.projectAssets.count == 2 && context.imageInputs().isEmpty)
        let second = ContextCaptureBatch(context: context, source: source)
        precondition(second.sessionID != first.sessionID && context.currentAssets.isEmpty)
        let two = ContextStroke(tool: .rectangle, points: [NSPoint(x: 150, y: 50), NSPoint(x: 230, y: 130)])
        _ = try second.confirm(strokes: [two], image: image, text: "", includeText: false, sourceURL: nil)
        let snapshot = context.requestSnapshot()
        precondition(snapshot.currentAssets.count == 1 && snapshot.imageInputs().count == 1)
        precondition(!snapshot.currentAssets.contains { oldIDs.contains($0.id) })
        let json = try JSONSerialization.jsonObject(with: Data(snapshot.modelContext(visual: true).utf8)) as! [String: Any]
        precondition((json["pointed_references"] as! [[String: Any]]).count == 1)
        let historical = (json["recent_shared_history"] as! [[String: Any]])[0]["historical_attachments"] as! [[String: Any]]
        precondition(historical.count == 2 && historical.allSatisfy { $0["image_sent"] as? Bool == false })
        let tray = context.requestSnapshot(focusedMaterialID: picture.id)
        precondition(tray.currentAssets.isEmpty && tray.imageInputs().count == 1)
        precondition(context.collectCurrentReferences(oldIDs).isEmpty)
        var strokes = [two]
        for i in 0..<7 { strokes.append(ContextStroke(tool: .rectangle, points: [NSPoint(x: 30 + i, y: 30), NSPoint(x: 60 + i, y: 60)])) }
        _ = try second.confirm(strokes: strokes, image: image, text: "", includeText: false, sourceURL: nil)
        precondition(context.currentAssets.count == 8 && context.projectAssets.count == 10)
        second.reconcileUndo(strokes: [])
        precondition(context.currentAssets.isEmpty && context.projectAssets.count == 10)
        second.finish(); precondition(context.flush() == nil)
        let restored = CompanionContext(store: CompanionProjectStore(directory: directory))
        precondition(restored.currentAssets.isEmpty && restored.projectAssets.count == 10 && restored.imageInputs().isEmpty)
        precondition(restored.turns[0].referenceIDs == oldIDs)
        precondition(restored.materials.count == 2 && restored.materials.contains { $0.note == "保留我的备注" && $0.image != nil })
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as! [String: Any]
        let entry = (manifest["entries"] as! [[String: Any]]).first!
        let path = directory.appendingPathComponent((entry["id"] as! String) + "/project.json")
        var doc = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        doc["assets"] = (doc["assets"] as! [[String: Any]]).map { value -> [String: Any] in var value = value; value.removeValue(forKey: "captureSessionID"); value.removeValue(forKey: "sourceBrowserBundleID"); return value }
        doc["turns"] = (doc["turns"] as! [[String: Any]]).map { value -> [String: Any] in var value = value; value.removeValue(forKey: "referenceIDs"); return value }
        try JSONSerialization.data(withJSONObject: doc).write(to: path, options: .atomic)
        let legacy = CompanionContext(store: CompanionProjectStore(directory: directory))
        precondition(!legacy.storageStatus.contains("暂停") && legacy.projectAssets.count == 10 && legacy.currentAssets.isEmpty)
        print("PASS: session-only attachments, archived history, explicit tray images, collection deduplication/source/notes, undo preservation, restart and legacy format")
    }
}

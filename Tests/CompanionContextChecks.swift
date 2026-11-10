import AppKit

@main struct CompanionContextChecks {
    static func main() throws {
        let context = CompanionContext()
        context.beginCaptureSession()
        let asset = CompanionContextAsset(title: "选中文字", text: "项目甲的私有选区", image: nil, sourceApp: "Test", sourceURL: "https://example.com/post?token=private", kind: "selected_text")
        precondition(context.add(asset)); precondition(context.add(asset)); precondition(context.currentAssets.count == 1)
        context.record(role: "user", text: "请记住项目甲的判断条件", purpose: "conversation")
        context.upsert(CompanionMaterial(id: "a", project: context.project, title: "待保存", text: "原文", note: "我的想法", area: "标题", image: nil, saved: false))
        let original = context.modelContext()
        precondition(original.contains("项目甲的私有选区") && original.contains("我的想法") && original.contains("conversation"))
        precondition(!original.contains("private"))
        context.setProject("乙", area: "新区域")
        precondition(context.currentAssets.isEmpty && context.count == 0)
        precondition(!context.modelContext().contains("项目甲"))
        context.setProject("校园文化节海报", area: "标题")
        context.beginCaptureSession()
        context.discardDraft("a"); precondition(context.materials.isEmpty)
        for n in 0..<8 { precondition(context.add(CompanionContextAsset(title: "\(n)", text: "\(n)", image: nil, sourceApp: "Test", sourceURL: nil, kind: "text"))) }
        precondition(!context.add(CompanionContextAsset(title: "超额", text: "超额", image: nil, sourceApp: "Test", sourceURL: nil, kind: "text")))
        context.clearAssets(); precondition(context.currentAssets.isEmpty)
        for n in 0..<8 { context.add(CompanionContextAsset(title: "大段 OCR \(n)", text: String(repeating: "长文字", count: 5000), image: nil, sourceApp: "Test", sourceURL: nil, kind: "text")) }
        precondition(context.modelContext().contains("请记住项目甲的判断条件"), "Large OCR erased shared conversation")
        context.clearAssets()

        // A flipped, two-colour display catches top/bottom confusion in screen cropping.
        let image = NSImage(size: NSSize(width: 200, height: 200), flipped: true) { _ in
            NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 200, height: 100).fill()
            NSColor.red.setFill(); NSRect(x: 0, y: 100, width: 200, height: 100).fill(); return true
        }
        let stroke = ContextStroke(tool: .rectangle, points: [NSPoint(x: 30, y: 20), NSPoint(x: 100, y: 60)])
        let crop = ContextCrop.crop(image, stroke: stroke)!
        precondition(crop.raw.size == NSSize(width: 94, height: 64))
        let bitmap = NSBitmapImageRep(data: crop.raw.tiffRepresentation!)!
        let colour = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        precondition(colour.blueComponent > 0.9 && colour.redComponent < 0.1, "Screen crop is vertically inverted")
        let outside = ContextStroke(tool: .rectangle, points: [NSPoint(x: -10, y: -10), NSPoint(x: 25, y: 20)])
        precondition(ContextCrop.rect(for: outside, in: image.size).minX == 0)
        precondition(CompanionContext.imageDataURL(crop.annotated)?.hasPrefix("data:image/jpeg;base64,") == true)
        let body = AgentTransport.requestBody(model: "fixture", instructions: "test", input: "selection", images: ["data:image/png;base64,eA=="])
        precondition(body["store"] as? Bool == false)
        let input = body["input"] as! [[String: Any]]
        let content = input[0]["content"] as! [[String: Any]]
        precondition(content.count == 2 && content[1]["type"] as? String == "input_image")
        let reviewContext = CompanionContext()
        reviewContext.beginCaptureSession()
        reviewContext.add(asset)
        let review = ContextReviewController(context: reviewContext)
        let root = review.window!.contentView!
        root.layoutSubtreeIfNeeded()
        let scroll = root.subviews.compactMap { $0 as? NSScrollView }.first!
        scroll.layoutSubtreeIfNeeded()
        precondition(scroll.documentView!.isFlipped)
        precondition(scroll.contentView.bounds.minY >= -1, "Context list leaves a blank area above its contents")
        if CommandLine.arguments.contains("--show-review") {
            review.window!.orderFrontRegardless()
            print("REVIEW_WINDOW=\(review.window!.windowNumber)"); fflush(stdout)
            RunLoop.current.run(until: Date().addingTimeInterval(5))
        }
        print("PASS: shared history / project isolation / context limits / crop orientation / multimodal payload")
    }
}

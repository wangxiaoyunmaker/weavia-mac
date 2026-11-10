import AppKit
import WebKit

@main struct WeaviaNativeCanvasChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        setenv("MOUSE_COMPANION_PROJECTS_DIR", root.appendingPathComponent("Projects").path, 1)
        _ = NSApplication.shared
        let context = CompanionContext()
        context.selectProject("校园文化节海报-" + UUID().uuidString)
        let firstProject = context.project
        let largeImages = CommandLine.arguments.contains("--large-images")
        func syntheticImage() -> NSImage {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 350, pixelsHigh: 350, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 1400, bitsPerPixel: 32)!
            for i in 0..<(350 * 350 * 4) { bitmap.bitmapData![i] = UInt8.random(in: 0...255) }
            let image = NSImage(size: NSSize(width: 350, height: 350)); image.addRepresentation(bitmap); return image
        }
        for index in 0..<24 {
            context.upsert(CompanionMaterial(id: String(format: "00000000-0000-4000-8000-%012d", index), project: context.project, title: "Synthetic material \(index)", text: "Fixture text", note: "", area: "Fixture", image: largeImages && index < 9 ? syntheticImage() : nil, saved: index < 12))
        }
        let secondProject = "Synthetic second project " + UUID().uuidString
        let secondMaterialID = "00000000-0000-4000-8000-999999999999"
        context.upsert(CompanionMaterial(id: secondMaterialID, project: secondProject, title: "Second project fixture", text: "Second project only", note: "", area: "Fixture", image: nil, saved: true))
        let pngBytes = context.materials.compactMap { $0.image?.tiffRepresentation }.compactMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }.reduce(0) { $0 + $1.count }
        print("FIXTURE: largeImages=\(largeImages) images=\(context.materials.filter { $0.image != nil }.count) pngBytes=\(pngBytes)")
        var controller = MacWorkspaceCanvas(context: context)
        var selectedProjects: [String] = []
        controller.onProjectSelected = { name in
            selectedProjects.append(name)
            context.selectProject(name)
        }
        func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        func evaluate(_ script: String) throws -> Any? {
            var done = false, value: Any?, failure: Error?
            controller.webView.evaluateJavaScript(script) { value = $0; failure = $1; done = true }
            let deadline = Date().addingTimeInterval(10)
            while !done && Date() < deadline { spin(0.05) }
            if let failure { throw failure }
            if !done { throw NSError(domain: "NativeChecks", code: 1) }
            return value
        }
        spin(12)
        if CommandLine.arguments.contains("--check-routing") {
            let home = try evaluate("location.hash !== '#cuppa' && !document.getElementById('project-desktop').hidden") as? Bool
            guard home == true else { print("FAIL: startup must show project home"); exit(1) }
            _ = try evaluate("document.getElementById('open-cuppa').click(); true")
            spin(2)
            let opened = try evaluate("location.hash === '#cuppa' && !document.getElementById('workspace').hidden") as? Bool
            guard opened == true else { print("FAIL: featured project click must enter canvas"); exit(1) }
            print("PASS: starts on project home and featured project opens canvas")
        }
        let result = try evaluate("JSON.stringify({url:location.href,ready:typeof cuppaReady !== 'undefined' && cuppaReady,bridge:typeof mouseCompanionMac,cardCount:typeof state !== 'undefined'?state.cards.length:-1,nativeCards:typeof state !== 'undefined'?state.cards.filter(c=>c.nativeMaterialId).length:-1,serializedLength:JSON.stringify(state).length,imageLengths:state.cards.map(c=>(c.image||'').length),domCards:document.querySelectorAll('.card').length,body:document.body.innerText.slice(-650)})")
        print("NATIVE_RESULT: \(result ?? "nil")")
        let quotaProbe = try evaluate("(()=>{try{localStorage.setItem(canvasStorageKey,JSON.stringify(state));return 'ok';}catch(e){return e.name+': '+e.message;}})()")
        print("CACHE_WRITE_PROBE: \(quotaProbe ?? "nil")")
        let disk = MacWorkspaceStorage.root.appendingPathComponent("Canvas")
        let files = (try? FileManager.default.contentsOfDirectory(at: disk, includingPropertiesForKeys: nil)) ?? []
        print("CANVAS_DISK: \(disk.path) files=\(files.count)")
        precondition(!controller.window.isVisible, "Must remain offscreen")
        let count = try evaluate("state.cards.filter(c=>c.nativeMaterialId).length") as? Int
        let domCount = try evaluate("document.querySelectorAll('.card').length") as? Int
        let imagesLoaded = try evaluate("Array.from(document.querySelectorAll('.card img')).filter(i=>i.complete && i.naturalWidth>0 && i.src.startsWith('weavia-asset:')).length") as? Int ?? 0
        print("RENDERED: cards=\(domCount ?? -1) nativeImagesLoaded=\(imagesLoaded)")
        if largeImages && CommandLine.arguments.contains("--check-routing") {
            guard imagesLoaded >= 9 else { print("FAIL: native images must render, not merely be stripped"); exit(1) }
        }
        guard count == 12, domCount == 12, files.contains(where: { $0.pathExtension == "json" }) else {
            print("FAIL: actual native handler did not round-trip 12 synthetic saved cards to disk")
            exit(1)
        }
        if CommandLine.arguments.contains("--check-routing") {
            _ = try evaluate("document.getElementById('projects').click(); true")
            spin(1)
            let clicked = try evaluate("(()=>{const tile=Array.from(document.querySelectorAll('.orbit-project')).find(e=>e.textContent.includes('Synthetic second project'));if(!tile)return false;tile.click();return true;})()") as? Bool
            guard clicked == true else { print("FAIL: second project peripheral tile missing"); exit(1) }
            spin(5)
            guard selectedProjects == [secondProject], context.project == secondProject else { print("FAIL: tile did not switch native context through callback"); exit(1) }
            _ = try evaluate("if(location.hash !== '#cuppa')document.getElementById('open-cuppa').click(); true")
            spin(2)
            let secondOpened = try evaluate("location.hash === '#cuppa' && !document.getElementById('workspace').hidden && state.cards.length === 1 && state.cards[0].nativeMaterialId === '00000000-0000-4000-8000-999999999999'") as? Bool
            guard secondOpened == true else { print("FAIL: second project canvas failed or leaked first project cards"); exit(1) }
            guard try MacCanvasSnapshotStore().load(secondProject) != nil else { print("FAIL: second project did not persist"); exit(1) }
            precondition(!controller.window.isVisible)
            print("PASS: peripheral tile switches native context through callback and opens isolated second project canvas")
            let originalController = controller
            let keys = ["design-canvas-v1:" + firstProject, "cuppa-mac-pending:" + firstProject]
            let encodedKeys = String(data: try JSONSerialization.data(withJSONObject: keys), encoding: .utf8)!
            _ = try evaluate("\(encodedKeys).forEach(k=>localStorage.removeItem(k)); true")
            // Mark the isolated disk snapshot to distinguish disk restoration from reimport.
            let snapshotStore = MacCanvasSnapshotStore()
            guard var persisted = try snapshotStore.load(firstProject), var persistedCards = persisted["cards"] as? [[String: Any]], persistedCards.count == 12 else { print("FAIL: first project's native snapshot missing"); exit(1) }
            persistedCards[0]["userNote"] = "Synthetic disk restore marker"
            persisted["cards"] = persistedCards
            try snapshotStore.save(persisted, project: firstProject)
            context.selectProject(firstProject)
            controller = MacWorkspaceCanvas(context: context)
            spin(12)
            _ = try evaluate("document.getElementById('open-cuppa').click(); true")
            spin(2)
            let reopenResult = try evaluate("JSON.stringify({cards:state.cards.length,nativeCards:state.cards.filter(c=>c.nativeMaterialId).length,uniqueIDs:new Set(state.cards.map(c=>c.id)).size,domCards:document.querySelectorAll('.card').length,nativeImagesLoaded:Array.from(document.querySelectorAll('.card img')).filter(i=>i.complete&&i.naturalWidth>0&&i.src.startsWith('weavia-asset:')).length,hasBase64:JSON.stringify(state).includes('data:image/'),diskMarker:state.cards.some(c=>c.userNote==='Synthetic disk restore marker')})") as? String ?? ""
            print("REOPEN_RESULT: \(reopenResult)")
            let reopened = try evaluate("state.cards.length===12 && new Set(state.cards.map(c=>c.id)).size===12 && document.querySelectorAll('.card').length===12 && !JSON.stringify(state).includes('data:image/') && state.cards.some(c=>c.userNote==='Synthetic disk restore marker')") as? Bool
            let reloadedImages = try evaluate("Array.from(document.querySelectorAll('.card img')).filter(i=>i.complete&&i.naturalWidth>0&&i.src.startsWith('weavia-asset:')).length") as? Int ?? 0
            guard reopened == true, !largeImages || reloadedImages >= 9 else { print("FAIL: fresh controller disk restore lost images, duplicated cards, retained inline images, or missed disk marker"); exit(1) }
            guard let restored = try MacCanvasSnapshotStore().load(firstProject), (restored["cards"] as? [[String: Any]])?.count == 12 else { print("FAIL: reopened native JSON has wrong card count"); exit(1) }
            precondition(!originalController.window.isVisible && !controller.window.isVisible)
            print("PASS: fresh controller restores native JSON after clearing only fixture browser cache; 12 unique cards, decoded native images, no base64, disk marker preserved, both windows invisible")
        }
        print("PASS: actual MacWorkspaceCanvas received ready, imported 12 saved native cards, saved canvas to isolated disk, and never displayed a window")
    }
}

import AppKit
import CryptoKit

/// Versioned local project documents. Image files are immutable, content addressed PNGs.
/// A serial writer commits images before JSON and the manifest last; flush is used on exit.
final class CompanionProjectStore {
    struct Manifest: Codable {
        var version = 1
        var activeProject: String
        var entries: [Entry]
    }
    struct Entry: Codable { let id: UUID; let name: String }
    struct Document: Codable {
        var version = 1
        let name: String
        let area: String
        let assets: [Asset]
        let materials: [Material]
        let turns: [CompanionContext.Turn]
    }
    struct Asset: Codable {
        let id: UUID; let title: String; let text: String; let image: String?
        let sourceApp: String; let sourceURL: String?; let kind: String
        var captureSessionID: UUID?
        var sourceBrowserBundleID: String?
    }
    struct Material: Codable {
        let id: String; let title: String; let text: String; let note: String; let area: String
        let image: String?; let saved: Bool; let metadata: CompanionMaterial.Metadata
    }
    struct Loaded {
        var activeProject = "校园文化节海报"
        var areas: [String: String] = [:]
        var assets: [CompanionContextAsset] = []
        var materials: [CompanionMaterial] = []
        var turns: [CompanionContext.Turn] = []
        var warning: String?
    }
    let directory: URL
    private let writer = DispatchQueue(label: "MouseCompanion.ProjectWriter", qos: .utility)
    private var entries: [Entry] = [] // main-thread snapshot preparation only
    private var imageCache: [String: (NSImage, String)] = [:]
    private var blocked = false
    private var preparationError: String?
    private let files = FileManager.default
    private var lastError: String? // confined to writer
    private var pendingImages: [URL: Data] = [:] // retry before publishing a document after an I/O failure
    private var recoveredFiles = Set<URL>()

    static func live() -> CompanionProjectStore {
        if let path = ProcessInfo.processInfo.environment["MOUSE_COMPANION_PROJECTS_DIR"], path.hasPrefix("/") {
            return CompanionProjectStore(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return CompanionProjectStore(directory: root.appendingPathComponent("com.designerworkspace.mousecompanion.prototype/Projects", isDirectory: true))
    }
    init(directory: URL) { self.directory = directory }

    func load() -> Loaded {
        var loaded = Loaded()
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard files.fileExists(atPath: manifestURL.path) || files.fileExists(atPath: manifestURL.appendingPathExtension("backup").path) else { return loaded }
        do {
            var recovered = false
            let manifest: Manifest = try read(directory.appendingPathComponent("manifest.json"), recovered: &recovered)
            guard manifest.version == 1 else { throw problem("项目数据来自较新版本，已停止覆盖写入。") }
            entries = manifest.entries
            loaded.activeProject = manifest.activeProject
            for entry in entries {
                let folder = projectDirectory(entry.id)
                let doc: Document = try read(folder.appendingPathComponent("project.json"), recovered: &recovered)
                guard doc.version == 1, doc.name == entry.name else { throw problem("项目文件版本或标识不一致，已停止覆盖写入。") }
                loaded.areas[entry.name] = doc.area
                for value in doc.assets {
                    let image = try loadImage(value.image, folder: folder)
                    loaded.assets.append(CompanionContextAsset(id: value.id, title: value.title, text: value.text, image: image, sourceApp: value.sourceApp, sourceURL: value.sourceURL, kind: value.kind, project: entry.name, captureSessionID: value.captureSessionID, sourceBrowserBundleID: value.sourceBrowserBundleID))
                }
                for value in doc.materials {
                    loaded.materials.append(CompanionMaterial(id: value.id, project: entry.name, title: value.title, text: value.text, note: value.note, area: value.area, image: try loadImage(value.image, folder: folder), saved: value.saved, metadata: value.metadata))
                }
                loaded.turns += doc.turns
            }
            loaded.turns.sort { $0.date < $1.date }
            if recovered { loaded.warning = "已从上一次完整备份恢复项目。" }
        } catch {
            // Never replace an unreadable project with an empty document.
            blocked = true
            loaded.warning = "项目读取未完成，原文件已保留，自动写入已暂停：\(error.localizedDescription)"
        }
        return loaded
    }

    func save(project: String, areas: [String: String], assets: [CompanionContextAsset], materials: [CompanionMaterial], turns: [CompanionContext.Turn], completion: @escaping (String?) -> Void) {
        guard !blocked else { completion("项目文件未能完整读取，自动写入已暂停；原文件未改动。"); return }
        do {
            let names = Set(areas.keys).union(assets.map(\.project)).union(materials.map(\.project)).union(turns.map(\.project)).union([project])
            for name in names.sorted() where !entries.contains(where: { $0.name == name }) { entries.append(Entry(id: UUID(), name: name)) }
            var imageWrites: [(URL, Data)] = []
            var liveImageKeys = Set<String>()
            func imageRef(_ image: NSImage?, key: String, folder: URL) throws -> String? {
                guard let image else { return nil }
                liveImageKeys.insert(key)
                if let cached = imageCache[key], cached.0 === image { return cached.1 }
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw problem("有一张图片无法编码，项目尚未保存。") }
                let filename = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined() + ".png"
                imageCache[key] = (image, filename)
                imageWrites.append((folder.appendingPathComponent("images/" + filename), png))
                return filename
            }
            let documents = try entries.map { entry -> (URL, Document) in
                let folder = projectDirectory(entry.id)
                let storedAssets = try assets.filter { $0.project == entry.name }.map { asset in
                    Asset(id: asset.id, title: asset.title, text: asset.text, image: try imageRef(asset.image, key: entry.id.uuidString + "selection" + asset.id.uuidString, folder: folder), sourceApp: asset.sourceApp, sourceURL: asset.sourceURL, kind: asset.kind, captureSessionID: asset.captureSessionID, sourceBrowserBundleID: asset.sourceBrowserBundleID)
                }
                let storedMaterials = try materials.filter { $0.project == entry.name }.map { item in
                    Material(id: item.id, title: item.title, text: item.text, note: item.note, area: item.area, image: try imageRef(item.image, key: entry.id.uuidString + "material" + item.id, folder: folder), saved: item.saved, metadata: item.metadata)
                }
                return (folder.appendingPathComponent("project.json"), Document(name: entry.name, area: areas[entry.name] ?? "标题排版探索区", assets: storedAssets, materials: storedMaterials, turns: turns.filter { $0.project == entry.name }))
            }
            imageCache = imageCache.filter { liveImageKeys.contains($0.key) }
            let manifest = Manifest(activeProject: project, entries: entries)
            // Encode before enqueueing; everything handed to the writer is immutable.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let encoded = try documents.map { ($0.0, try encoder.encode($0.1)) }
            let manifestData = try encoder.encode(manifest)
            preparationError = nil
            writer.async { [self] in
                for (url, data) in imageWrites { pendingImages[url] = data }
                do {
                    try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    for (url, data) in pendingImages {
                        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        if !files.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic); try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
                    }
                    pendingImages.removeAll()
                    for (url, data) in encoded { try write(data, to: url) }
                    try write(manifestData, to: directory.appendingPathComponent("manifest.json"))
                    lastError = nil
                } catch { lastError = "项目保存失败：\(error.localizedDescription)" }
                let error = lastError
                DispatchQueue.main.async { completion(error) }
            }
        } catch { imageCache.removeAll(); preparationError = error.localizedDescription; completion(error.localizedDescription) }
    }
    @discardableResult func flush() -> String? {
        let error = writer.sync { lastError }
        return blocked ? "项目读取失败，原文件已保留，写入已暂停。" : preparationError ?? error
    }
    private func projectDirectory(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func write(_ data: Data, to url: URL) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if files.fileExists(atPath: url.path), !recoveredFiles.contains(url) {
            let previous = try Data(contentsOf: url)
            if previous == data { return }
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        recoveredFiles.remove(url)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func read<T: Decodable>(_ url: URL, recovered: inout Bool) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) }
        catch {
            let value = try JSONDecoder().decode(T.self, from: Data(contentsOf: url.appendingPathExtension("backup")))
            recovered = true; recoveredFiles.insert(url); return value
        }
    }
    private func loadImage(_ filename: String?, folder: URL) throws -> NSImage? {
        guard let filename else { return nil }
        guard filename.range(of: "^[a-f0-9]{64}\\.png$", options: .regularExpression) != nil,
              let image = NSImage(contentsOf: folder.appendingPathComponent("images/" + filename)) else { throw problem("项目图片文件缺失或无法读取。") }
        return image
    }
    private func problem(_ text: String) -> Error { NSError(domain: "CompanionProjectStore", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

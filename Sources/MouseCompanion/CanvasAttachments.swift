import AppKit
import PDFKit
import ImageIO
import CryptoKit
import WebKit

/// Immutable, local-only originals. IDs, never supplied paths, address attachments.
/// Deleting a card deliberately retains its original so undo and backups can restore it.
final class CanvasAttachmentStore {
    static let maximumBytes = 50 * 1024 * 1024
    struct Record: Codable {
        let version: Int
        let id: String
        let kind: String
        let filename: String
        let fileExtension: String
        let byteCount: Int
        let sha256: String
        let importedAt: String
        let pageCount: Int?
    }
    let directory: URL
    init(directory: URL = MacWorkspaceStorage.root.appendingPathComponent("Attachments", isDirectory: true)) { self.directory = directory }
    private func folder(_ project: String) -> URL {
        let key = SHA256.hash(data: Data(project.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key, isDirectory: true)
    }
    private func failure(_ message: String) -> Error { NSError(domain: "CanvasAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func load(_ id: String, project: String) throws -> Record {
        guard UUID(uuidString: id) != nil else { throw failure("原件标识无效。") }
        let data = try Data(contentsOf: folder(project).appendingPathComponent(id + ".json"))
        let value = try JSONDecoder().decode(Record.self, from: data)
        guard value.version == 1, value.id == id, ["image", "pdf"].contains(value.kind),
              ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "pdf"].contains(value.fileExtension) else { throw failure("原件版本不支持，原文件已保留。") }
        return value
    }
    func original(_ id: String, project: String) throws -> URL {
        let record = try load(id, project: project)
        let result = folder(project).appendingPathComponent(id + "." + record.fileExtension)
        guard FileManager.default.fileExists(atPath: result.path) else { throw failure("本机原件缺失，请重新选择文件。") }
        return result
    }
    func thumbnail(_ id: String, project: String) throws -> Data {
        _ = try load(id, project: project)
        return try Data(contentsOf: folder(project).appendingPathComponent(id + ".preview.png"))
    }
    func importFile(_ url: URL, kind: String, project: String) throws -> Record {
        guard url.isFileURL, ["image", "pdf"].contains(kind) else { throw failure("请选择本机图片或 PDF。") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= Self.maximumBytes else { throw failure("请选择 50 MB 以内的非空文件。") }
        let ext = url.pathExtension.lowercased()
        guard (kind == "pdf" && ext == "pdf") || (kind == "image" && ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff"].contains(ext)) else { throw failure("此文件类型不支持，请选择常见图片格式或 PDF。") }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else { throw failure("文件超出 50 MB，未导入。") }
        let preview: NSImage
        var pages: Int?
        if kind == "pdf" {
            guard data.starts(with: Data("%PDF-".utf8)), let pdf = PDFDocument(data: data), !pdf.isLocked,
                  pdf.pageCount > 0, let first = pdf.page(at: 0) else { throw failure("PDF 无法读取或已加密，请选择可直接打开的论文。") }
            pages = pdf.pageCount
            preview = first.thumbnail(of: NSSize(width: 640, height: 800), for: .cropBox)
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0, width.doubleValue * height.doubleValue <= 80_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw failure("图片无法解码或超过 8000 万像素，未导入。") }
            preview = NSImage(cgImage: image, size: .zero)
        }
        guard let tiff = preview.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("无法生成本机预览，未添加卡片。") }
        let record = Record(version: 1, id: UUID().uuidString, kind: kind, filename: url.lastPathComponent, fileExtension: ext, byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), importedAt: ISO8601DateFormatter().string(from: Date()), pageCount: pages)
        let dest = folder(project)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try data.write(to: dest.appendingPathComponent(record.id + "." + ext), options: .atomic)
        try png.write(to: dest.appendingPathComponent(record.id + ".preview.png"), options: .atomic)
        try JSONEncoder().encode(record).write(to: dest.appendingPathComponent(record.id + ".json"), options: .atomic)
        return record
    }
    func payload(_ record: Record, project: String) -> [String: Any] {
        var url = URLComponents(); url.scheme = "weavia-file"; url.host = "preview"; url.path = "/" + record.id + ".png"; url.queryItems = [URLQueryItem(name: "project", value: project)]
        var value: [String: Any] = ["version": 1, "id": record.id, "kind": record.kind, "filename": record.filename, "byteCount": record.byteCount, "importedAt": record.importedAt, "previewURL": url.url!.absoluteString]
        if let count = record.pageCount { value["pageCount"] = count }
        return value
    }
}

/// Only thumbnails for the selected project can reach the page. Original PDFs stay native.
final class CanvasAttachmentHandler: NSObject, WKURLSchemeHandler {
    let store: CanvasAttachmentStore
    var project = ""
    init(store: CanvasAttachmentStore) { self.store = store }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "weavia-file", parts.host == "preview", parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.queryItems?.count == 1, parts.queryItems?.first?.name == "project", parts.queryItems?.first?.value == project,
              url.pathExtension == "png", url.pathComponents.count == 2 else { task.didFailWithError(URLError(.noPermissionsToReadFile)); return }
        let id = url.deletingPathExtension().lastPathComponent
        do { let data = try store.thumbnail(id, project: project)
            task.didReceive(URLResponse(url: url, mimeType: "image/png", expectedContentLength: data.count, textEncodingName: nil)); task.didReceive(data); task.didFinish()
        } catch { task.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

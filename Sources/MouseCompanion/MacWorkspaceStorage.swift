import Foundation
import CryptoKit

/// A separate data root keeps the shipped Mac prototype and this workspace independent.
/// Existing projects are copied once, never moved or rewritten in the original location.
enum MacWorkspaceStorage {
    static var root: URL {
        if let custom = ProcessInfo.processInfo.environment["MOUSE_COMPANION_PROJECTS_DIR"], custom.hasPrefix("/") {
            return URL(fileURLWithPath: custom).deletingLastPathComponent().appendingPathComponent("CanvasWorkspace")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.designerworkspace.mousecompanion.macworkspace", isDirectory: true)
    }
    static func prepareLegacyImport() throws {
        guard ProcessInfo.processInfo.environment["MOUSE_COMPANION_PROJECTS_DIR"] == nil else { return }
        let destination = root.appendingPathComponent("Projects", isDirectory: true)
        let legacy = root.deletingLastPathComponent().appendingPathComponent("com.designerworkspace.mousecompanion.prototype/Projects", isDirectory: true)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path), fm.fileExists(atPath: legacy.path) else { return }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent("Projects-import-" + UUID().uuidString, isDirectory: true)
        try fm.copyItem(at: legacy, to: staging)
        try fm.moveItem(at: staging, to: destination)
    }
    static func projectStore() -> CompanionProjectStore {
        if let path = ProcessInfo.processInfo.environment["MOUSE_COMPANION_PROJECTS_DIR"], path.hasPrefix("/") {
            return CompanionProjectStore(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
        return CompanionProjectStore(directory: root.appendingPathComponent("Projects", isDirectory: true))
    }
    static func inheritInterfacePreferences() {
        let legacy = UserDefaults(suiteName: "com.designerworkspace.mousecompanion.prototype")
        for key in ["agent-api-base-url", "agent-api-model"] where UserDefaults.standard.object(forKey: key) == nil {
            if let value = legacy?.string(forKey: key) { UserDefaults.standard.set(value, forKey: key) }
        }
    }
}

final class MacCanvasSnapshotStore {
    let directory: URL
    private var blockedProjects = Set<String>()
    private var recoveredProjects = Set<String>()
    init(directory: URL = MacWorkspaceStorage.root.appendingPathComponent("Canvas", isDirectory: true)) { self.directory = directory }
    private func location(_ project: String) -> URL {
        let key = SHA256.hash(data: Data(project.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".json")
    }
    private func decoded(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["cards"] is [[String: Any]], let drafts = object["drafts"] as? [String: Any],
              drafts["personal"] is [String: Any], drafts["agent"] is [String: Any] else { throw failure("画布文件格式不正确") }
        return object
    }
    func load(_ project: String) throws -> [String: Any]? {
        let url = location(project), backup = url.appendingPathExtension("backup"), fm = FileManager.default
        guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: backup.path) else { return nil }
        do { return try decoded(Data(contentsOf: url)) }
        catch {
            if let data = try? Data(contentsOf: backup), let object = try? decoded(data) {
                recoveredProjects.insert(project); return object
            }
            blockedProjects.insert(project)
            throw failure("画布数据暂时无法恢复，原文件已保留，已停止覆盖。")
        }
    }
    func save(_ object: [String: Any], project: String) throws {
        guard !blockedProjects.contains(project) else { throw failure("请先恢复画布文件，当前原数据已保护，不会覆盖。") }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        _ = try decoded(data)
        guard data.count <= 64 * 1024 * 1024 else { throw failure("画布内容过大，尚未保存。请减少单张图片大小后重试。") }
        let url = location(project), fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path), !recoveredProjects.contains(project) {
            let previous = try Data(contentsOf: url)
            if previous == data { return }
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        recoveredProjects.remove(project)
    }
    private func failure(_ text: String) -> Error { NSError(domain: "MacCanvasStore", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

import Foundation
import CryptoKit
import Darwin

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
    private let stateLock = NSRecursiveLock()
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
        stateLock.lock(); defer { stateLock.unlock() }
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
    /// Identity is the complete canonical content, never a revision counter.
    static func token(for snapshot: [String: Any]?) throws -> String {
        guard let snapshot else { return "missing" }
        return digest(try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]))
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func loadWithToken(_ project: String) throws -> (snapshot: [String: Any]?, token: String) {
        let snapshot = try load(project)
        return (snapshot, try Self.token(for: snapshot))
    }
    @discardableResult
    func saveChecked(_ object: [String: Any], project: String, expectedToken: String) throws -> String {
        try withProjectWriteLock(project) {
            try saveCheckedUnlocked(object, project: project, expectedToken: expectedToken)
        }
    }
    private func saveCheckedUnlocked(_ object: [String: Any], project: String, expectedToken: String) throws -> String {
        let current = try loadWithToken(project)
        guard current.token == expectedToken else {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            var details: [String: Any] = [:]
            do {
                details["recoveryID"] = try preserveRecoveryUnlocked(pendingRaw: String(decoding: data, as: UTF8.self),
                    baseCanvasToken: expectedToken, reason: "native-content-changed", project: project)
                details[NSLocalizedDescriptionKey] = "本机画布已变化，已保留待恢复副本，停止覆盖。"
            } catch {
                details[NSLocalizedDescriptionKey] = "本机画布已变化，停止覆盖。待恢复副本尚未归档，请保留当前页面并重试。"
                details[NSUnderlyingErrorKey] = error
            }
            throw NSError(domain: "MacCanvasStore", code: 409, userInfo: details)
        }
        try saveUnlocked(object, project: project)
        return try Self.token(for: object)
    }
    /// Append-only, content-addressed records. Raw strings are not parsed or normalized.
    /// Neither callers nor web content can choose a filesystem destination.
    @discardableResult
    func preserveRecovery(pendingRaw: String, cachedRaw: String? = nil, baseCanvasToken: String? = nil,
                          reason: String? = nil, project: String) throws -> String {
        try withProjectWriteLock(project) {
            try preserveRecoveryUnlocked(pendingRaw: pendingRaw, cachedRaw: cachedRaw,
                baseCanvasToken: baseCanvasToken, reason: reason, project: project)
        }
    }
    private func preserveRecoveryUnlocked(pendingRaw: String, cachedRaw: String? = nil, baseCanvasToken: String? = nil,
                                         reason: String? = nil, project: String) throws -> String {
        let limit = 64 * 1024 * 1024
        guard pendingRaw.utf8.count <= limit, (cachedRaw?.utf8.count ?? 0) <= limit,
              (baseCanvasToken?.utf8.count ?? 0) <= 1024, (reason?.utf8.count ?? 0) <= 4096 else {
            throw failure("待恢复内容过大，尚未归档；原内容保持不变。")
        }
        var record: [String: Any] = ["version": 1, "projectId": project, "pendingRaw": pendingRaw]
        if let cachedRaw { record["cachedRaw"] = cachedRaw }
        if let baseCanvasToken { record["baseCanvasToken"] = baseCanvasToken }
        if let reason { record["reason"] = reason }
        do {
            let current = try loadWithToken(project)
            record["currentCanvasToken"] = current.token
            record["currentNativeSnapshot"] = (current.snapshot as Any?) ?? NSNull()
        } catch {
            // Corruption must not prevent preserving an otherwise irreplaceable web draft.
            record["currentStorageError"] = error.localizedDescription
            let url = location(project)
            for (key, source) in [("currentNativeRawBase64", url), ("currentBackupRawBase64", url.appendingPathExtension("backup"))] {
                if FileManager.default.fileExists(atPath: source.path) {
                    let data = try Data(contentsOf: source)
                    guard data.count <= limit else { throw failure("本机文件过大，尚未归档；原内容保持不变。") }
                    record[key] = data.base64EncodedString()
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        let recoveryID = Self.digest(data)
        let folder = directory.appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent(Self.digest(Data(project.utf8)), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(recoveryID + ".json")
        do { try data.write(to: target, options: .withoutOverwriting) }
        catch {
            // An identical repeated request is idempotent, never an overwrite.
            guard let existing = try? Data(contentsOf: target), existing == data else { throw error }
        }
        return recoveryID
    }
    func save(_ object: [String: Any], project: String) throws {
        try withProjectWriteLock(project) { try saveUnlocked(object, project: project) }
    }
    private func saveUnlocked(_ object: [String: Any], project: String) throws {
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
    /// All cooperating store instances/processes use the same persistent per-project lock.
    /// Hold it across token read, backup rotation, replacement, and conflict preservation.
    /// Never unlink lock files: replacing a locked inode would split mutual exclusion.
    /// This advisory lock cannot stop tools that write JSON directly without participating;
    /// offline import/restore must continue to require the application to be closed.
    private func withProjectWriteLock<T>(_ project: String, _ operation: () throws -> T) throws -> T {
        stateLock.lock(); defer { stateLock.unlock() }
        let canonical = directory.standardizedFileURL.resolvingSymlinksInPath()
        let locks = canonical.deletingLastPathComponent()
            .appendingPathComponent("." + canonical.lastPathComponent + "-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
        let path = locks.appendingPathComponent(Self.digest(Data(project.utf8)) + ".lock").path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = flock(fd, LOCK_UN) }
        return try operation()
    }
    private func failure(_ text: String) -> Error { NSError(domain: "MacCanvasStore", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

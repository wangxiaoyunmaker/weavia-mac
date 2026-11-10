import Foundation

@main struct MacWorkspaceStorageChecks {
    static func main() throws {
        func check(_ value: Bool, _ message: String = "Check failed") { precondition(value, message) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mac-workspace-storage-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MacCanvasSnapshotStore(directory: directory)
        let first: [String: Any] = ["version": 1, "drafts": ["personal": ["text": ""], "agent": ["text": ""]], "cards": [["id": "first"]]]
        let second: [String: Any] = ["version": 1, "drafts": ["personal": ["text": ""], "agent": ["text": ""]], "cards": [["id": "second"]]]
        func encoded(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        func same(_ object: [String: Any]?, _ expected: [String: Any]) throws -> Bool { guard let object else { return false }; return try encoded(object) == encoded(expected) }
        let project = "../甲/含路径字符"
        check(try store.load(project) == nil)
        try store.save(first, project: project)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(files.count == 1 && files[0].pathExtension == "json" && files[0].lastPathComponent.count == 69)
        let primary = files[0], backup = primary.appendingPathExtension("backup")
        check(try same(MacCanvasSnapshotStore(directory: directory).load(project), first))
        check(try store.load("乙") == nil)
        try store.save(second, project: project)
        check(try Data(contentsOf: backup) == encoded(first))
        try store.save(second, project: project)
        check(try Data(contentsOf: backup) == encoded(first), "Identical saves should not rotate backups")
        print("PASS: hashed paths, project isolation, restart round-trip, backup rotation, identical save")
        try Data("corrupt primary".utf8).write(to: primary)
        let recovered = MacCanvasSnapshotStore(directory: directory)
        check(try same(recovered.load(project), first))
        try recovered.save(second, project: project)
        check(try Data(contentsOf: backup) == encoded(first), "Recovery save replaced valid backup with corrupt primary")
        print("PASS: recovery preserves known-good backup")
        try FileManager.default.removeItem(at: primary)
        check(try same(MacCanvasSnapshotStore(directory: directory).load(project), first), "Missing primary must recover backup")
        print("PASS: backup-only recovery")
        try Data("corrupt primary".utf8).write(to: primary)
        try Data("corrupt backup".utf8).write(to: backup)
        let blocked = MacCanvasSnapshotStore(directory: directory)
        do { _ = try blocked.load(project); preconditionFailure("Corruption accepted") } catch {}
        do { try blocked.save(second, project: project); preconditionFailure("Protected corruption overwritten") } catch {}
        check(try String(contentsOf: primary) == "corrupt primary")
        check(try String(contentsOf: backup) == "corrupt backup")
        print("PASS: unrepairable corruption blocks overwrite")
    }
}

import Foundation

@main struct WeaviaSnapshotIdentityChecks {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("weavia-snapshot-identity-" + UUID().uuidString)
        defer { try? fm.removeItem(at: directory) }
        let store = MacCanvasSnapshotStore(directory: directory), project = "../isolated/项目"
        func snapshot(_ text: String) -> [String: Any] {
            ["revision": 1, "cards": [["id": "a", "text": text]], "drafts": ["personal": [:], "agent": [:]]]
        }
        // Child mode shares only a disposable directory and uses the public store API.
        if CommandLine.arguments.count == 6, CommandLine.arguments[1] == "--race-worker" {
            let root = URL(fileURLWithPath: CommandLine.arguments[2])
            let expected = CommandLine.arguments[3], name = CommandLine.arguments[4], raceProject = CommandLine.arguments[5]
            try Data().write(to: root.appendingPathComponent("ready-" + name))
            let deadline = Date().addingTimeInterval(20)
            while !fm.fileExists(atPath: root.appendingPathComponent("go").path) {
                guard Date() < deadline else { exit(9) }; Thread.sleep(forTimeInterval: 0.005)
            }
            do {
                _ = try MacCanvasSnapshotStore(directory: root.appendingPathComponent("Canvas"))
                    .saveChecked(snapshot(name), project: raceProject, expectedToken: expected)
                exit(0)
            } catch {
                let error = error as NSError
                exit(error.domain == "MacCanvasStore" && error.code == 409 ? 3 : 8)
            }
        }
        func check(_ result: Bool, _ message: String) { precondition(result, message) }
        func rejects(_ operation: () throws -> Void) {
            do { try operation(); preconditionFailure("Unexpected write accepted") } catch {}
        }
        let first = snapshot("first"), second = snapshot("second"), candidate = snapshot("queued")
        let reordered: [String: Any] = ["drafts": ["agent": [:], "personal": [:]], "cards": [["text": "first", "id": "a"]], "revision": 1]
        check(try MacCanvasSnapshotStore.token(for: nil) == "missing", "Absent token")
        check(try MacCanvasSnapshotStore.token(for: first) == MacCanvasSnapshotStore.token(for: reordered), "Canonical dictionary ordering")
        let initial = try store.loadWithToken(project)
        try store.save(first, project: project)
        rejects { _ = try store.saveChecked(candidate, project: project, expectedToken: initial.token) }
        check(try store.loadWithToken(project).token == MacCanvasSnapshotStore.token(for: first), "Missing-to-created race changed disk")
        let stale = try store.loadWithToken(project).token
        try store.save(second, project: project)
        rejects { _ = try store.saveChecked(candidate, project: project, expectedToken: stale) }
        check(try store.loadWithToken(project).token == MacCanvasSnapshotStore.token(for: second), "Same-revision edit changed disk")
        var token = try store.loadWithToken(project).token
        token = try store.saveChecked(first, project: project, expectedToken: token)
        token = try store.saveChecked(candidate, project: project, expectedToken: token)
        check(try token == store.loadWithToken(project).token, "Sequential writes failed")
        let raw = "  {\"cards\": [ ]}\n待恢复 🌿", cache = "not even JSON\n  exact bytes"
        let recoveryID = try store.preserveRecovery(pendingRaw: raw, cachedRaw: cache, baseCanvasToken: stale, reason: "test", project: project)
        let files = fm.enumerator(at: directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
        let file = files.first { $0.deletingPathExtension().lastPathComponent == recoveryID }!
        let original = try Data(contentsOf: file)
        let attributes = try fm.attributesOfItem(atPath: file.path)
        let record = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        check(record["pendingRaw"] as? String == raw && record["cachedRaw"] as? String == cache, "Raw strings were normalized")
        check(record["currentCanvasToken"] as? String == token, "Current snapshot token missing")
        check(record["currentNativeSnapshot"] is [String: Any], "Current native snapshot missing")
        let again = try store.preserveRecovery(pendingRaw: raw, cachedRaw: cache, baseCanvasToken: stale, reason: "test", project: project)
        check(again == recoveryID && recoveryID.count == 64 && !recoveryID.contains("/"), "Recovery identity/path leak")
        check(try Data(contentsOf: file) == original, "Archive overwritten")
        check(try fm.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == attributes[.modificationDate] as? Date, "Archive rewritten")
        check(try store.loadWithToken(project).token == token, "Recovery mutated primary")
        rejects { _ = try store.preserveRecovery(pendingRaw: String(repeating: "x", count: 64 * 1024 * 1024 + 1), project: project) }
        print("PASS: canonical identity, same-revision conflict, creation race, FIFO saves, exact append-only recovery, raw limit")
        // Independent instances in one process must not both accept one base token.
        let parallelProject = "thread-race"
        try store.save(first, project: parallelProject)
        let parallelToken = try store.loadWithToken(parallelProject).token
        let group = DispatchGroup(), resultLock = NSLock()
        var accepted = 0, conflicts = 0, unexpected = 0
        for index in 0..<16 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    _ = try MacCanvasSnapshotStore(directory: directory).saveChecked(snapshot("thread-\(index)"),
                        project: parallelProject, expectedToken: parallelToken)
                    resultLock.lock(); accepted += 1; resultLock.unlock()
                } catch {
                    let error = error as NSError
                    resultLock.lock()
                    if error.domain == "MacCanvasStore" && error.code == 409 { conflicts += 1 } else { unexpected += 1 }
                    resultLock.unlock()
                }
            }
        }
        check(group.wait(timeout: .now() + 20) == .success, "Thread race deadlocked")
        check(accepted == 1 && conflicts == 15 && unexpected == 0, "Independent stores both accepted stale base")
        // Distinct processes start from the same token; only one may commit.
        for round in 0..<6 {
            let root = directory.appendingPathComponent("process-race-\(round)")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let raceStore = MacCanvasSnapshotStore(directory: root.appendingPathComponent("Canvas"))
            let raceProject = "process-race"
            try raceStore.save(first, project: raceProject)
            let base = try raceStore.loadWithToken(raceProject).token
            var children: [Process] = []
            for name in ["left", "right"] {
                let child = Process()
                child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                child.arguments = ["--race-worker", root.path, base, name, raceProject]
                try child.run(); children.append(child)
            }
            let deadline = Date().addingTimeInterval(20)
            while !["left", "right"].allSatisfy({ fm.fileExists(atPath: root.appendingPathComponent("ready-" + $0).path) }) {
                check(Date() < deadline, "Child startup timed out"); Thread.sleep(forTimeInterval: 0.005)
            }
            try Data().write(to: root.appendingPathComponent("go"))
            children.forEach { $0.waitUntilExit() }
            check(children.map { $0.terminationStatus }.sorted() == [0, 3], "Cross-process CAS accepted twice")
            let disk = try raceStore.loadWithToken(raceProject)
            check(disk.token != base, "Race winner missing")
            let primary = try fm.contentsOfDirectory(at: root.appendingPathComponent("Canvas"), includingPropertiesForKeys: nil).first { $0.pathExtension == "json" }!
            let backup = try JSONSerialization.jsonObject(with: Data(contentsOf: primary.appendingPathExtension("backup"))) as! [String: Any]
            check(try MacCanvasSnapshotStore.token(for: backup) == base, "Backup no longer matches transaction base")
        }
        print("PASS: independent-store and cross-process CAS races; exactly one winner; backup preserved")

    }
}

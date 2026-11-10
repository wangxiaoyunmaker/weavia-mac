import AppKit

@main
struct PreviewChecks {
    static func main() {
        _ = NSApplication.shared
        var requests: [CapturePreviewRequest] = []
        var pending = CommandLine.arguments.count - 1
        var failures = 0
        var cancelledUpdates = 0
        let cancelled = CapturePreviewRequest { _ in cancelledUpdates += 1 }
        cancelled.start(url: URL(string: "https://example.com")!, imageURL: false)
        cancelled.cancel()
        for input in CommandLine.arguments.dropFirst() {
            guard let url = URL(string: input) else { fatalError("Invalid fixture URL") }
            let imageURL = ["png", "jpg", "jpeg"].contains(url.pathExtension)
            var updates = 0
            let request = CapturePreviewRequest { result in
                updates += 1
                if result.finished {
                    print("\(url.host ?? "fixture"): title=\(result.title ?? "nil") image=\(result.image != nil) failed=\(result.failed) updates=\(updates)")
                    if url.scheme == "file", !result.failed { failures += 1 }
                    if url.host == "example.com", result.title?.isEmpty != false { failures += 1 }
                    if url.host == "www.xiaohongshu.com", input.contains("6af1799b000000002c02b2b7"), !result.failed { failures += 1 }
                    if url.path == "/fixture.png", result.image == nil || result.failed { failures += 1 }
                    if url.path == "/missing.png", !result.failed { failures += 1 }
                    pending -= 1
                }
            }
            requests.append(request)
            request.start(url: url, imageURL: imageURL)
        }
        let deadline = Date().addingTimeInterval(22)
        while pending > 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if pending > 0 { failures += 1 }
        requests.forEach { $0.cancel() }
        if cancelledUpdates != 0 { failures += 1 }
        if failures > 0 { exit(1) }
    }
}

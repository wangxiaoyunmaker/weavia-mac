import AppKit
import LinkPresentation

/// All updates are delivered on the main queue. No page scripts or browser automation are used.
final class CapturePreviewRequest {
    struct Update {
        var title: String?
        var image: NSImage?
        var finished: Bool
        var failed: Bool
    }

    private let provider = LPMetadataProvider()
    private var imageTask: URLSessionDataTask?
    private var watchdog: DispatchWorkItem?
    private var cancelled = false
    private var finished = false
    private let completion: (Update) -> Void

    init(completion: @escaping (Update) -> Void) {
        self.completion = completion
    }

    func start(url: URL, imageURL: Bool) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            emit(Update(finished: true, failed: true))
            return
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.provider.cancel()
            self.imageTask?.cancel()
            self.emit(Update(finished: true, failed: true))
        }
        watchdog = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: timeout)

        if imageURL {
            fetchImage(url: url)
            return
        }

        provider.timeout = 12
        provider.shouldFetchSubresources = true
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            DispatchQueue.main.async {
                guard let self, !self.cancelled, !self.finished else { return }
                guard let metadata else {
                    // Many browser/CDN image URLs have no file extension.
                    self.fetchImage(url: url)
                    return
                }
                let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let validTitle = title.flatMap { $0.isEmpty ? nil : $0 }
                // Error/login pages can also advertise a title and an OG image.
                // Do not present their illustration as the collected content.
                let errorTitles = ["你访问的页面不见了", "页面不存在", "内容不存在", "内容已删除", "访问受限", "安全验证", "请登录", "404 not found", "page not found", "access denied", "sign in to", "log in to"]
                if let validTitle, errorTitles.contains(where: { validTitle.lowercased().contains($0) }) {
                    self.emit(Update(finished: true, failed: true))
                    return
                }
                guard let images = metadata.imageProvider, images.canLoadObject(ofClass: NSImage.self) else {
                    if validTitle == nil {
                        self.fetchImage(url: url)
                        return
                    }
                    self.emit(Update(title: validTitle, finished: true, failed: validTitle == nil))
                    return
                }
                self.emit(Update(title: validTitle, finished: false, failed: false))
                images.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    DispatchQueue.main.async {
                        let image = object as? NSImage
                        self?.emit(Update(title: validTitle, image: image, finished: true, failed: validTitle == nil && image == nil))
                    }
                }
            }
        }
    }

    private func fetchImage(url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        imageTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let ok = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
                let image = ok ? data.flatMap(NSImage.init(data:)) : nil
                self.emit(Update(image: image, finished: true, failed: image == nil))
            }
        }
        imageTask?.resume()
    }

    func cancel() {
        cancelled = true
        watchdog?.cancel()
        provider.cancel()
        imageTask?.cancel()
    }

    private func emit(_ update: Update) {
        guard !cancelled, !finished else { return }
        if update.finished {
            finished = true
            watchdog?.cancel()
        }
        completion(update)
    }

    deinit { cancel() }
}

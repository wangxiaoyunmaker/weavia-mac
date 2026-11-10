import AppKit
import WebKit
import CryptoKit
import PDFKit
import UniformTypeIdentifiers

/// Route canvas shortcuts before AppKit's generic Edit menu, while leaving
/// WebKit text-field undo and every other app window on the normal responder chain.
final class WeaviaCanvasWindow: NSWindow {
    var onCanvasHistory: ((Bool) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers?.lowercased() == "z", modifiers.contains(.command),
           !modifiers.contains(.option), !modifiers.contains(.control), let onCanvasHistory {
            onCanvasHistory(modifiers.contains(.shift)); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Hosts the teammate's CUPPA canvas without changing the native companion and tray UI.
final class MacWorkspaceCanvas: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    let window: NSWindow
    private(set) var webView: WKWebView!
    private let context: CompanionContext
    private let assets = MacWorkspaceAssetHandler()
    private let attachments = CanvasAttachmentStore()
    private lazy var attachmentHandler = CanvasAttachmentHandler(store: attachments)
    private var attachmentWindows: [NSWindow] = []
    private var importingAttachment = false
    private var destination = "projects"
    private let snapshots = MacCanvasSnapshotStore()
    private var resourceRoot: URL?
    private var isReady = false
    private var loadedProject = ""
    private var observation: UUID?
    private var publishWork: DispatchWorkItem?
    private var revision = 0
    private var mode = "focus"
    private var selectedCards: [[String: Any]] = []
    private var selectionSession = ""
    private var selectionCards: [[String: Any]] = []
    private var selectionBounds: [String: Any]?
    private var windowObservers: [NSObjectProtocol] = []
    var onSelection: ((NSRect, [[String: Any]], String, Bool, Bool) -> NSPoint?)?
    var onSelectionEnded: (() -> Void)?
    var onProjectSelected: ((String) -> Void)?
    var onSmartTags: (([String: Any], String) -> Void)?
    var onCancelSmartTags: ((String?) -> Void)?
    var onAgent: ((String, [[String: Any]], String) -> Void)?
    var onWorkMode: ((Bool) -> Void)?
    var onSettings: (() -> Void)?
    var onHistory: (() -> Void)?
    var onCancelAgent: (() -> Void)?
    var onOpenMaterial: ((String) -> Void)?

    init(context: CompanionContext, websiteDataStore: WKWebsiteDataStore = .default()) {
        self.context = context
        window = WeaviaCanvasWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "WEAVIA · " + context.project
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.center()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = websiteDataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(self, name: "mouseCompanion")
        config.setURLSchemeHandler(assets, forURLScheme: "weavia-asset")
        config.setURLSchemeHandler(attachmentHandler, forURLScheme: "weavia-file")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.setAccessibilityLabel("WEAVIA 项目画布")
        window.contentView = webView
        (window as? WeaviaCanvasWindow)?.onCanvasHistory = { [weak self] redo in
            guard let self else { return }
            self.webView.evaluateJavaScript("globalThis.cuppaCanvasHistory?.keyCommand(\(redo ? "true" : "false")) || false") { handled, _ in
                if handled as? Bool != true {
                    NSApp.sendAction(Selector(redo ? "redo:" : "undo:"), to: nil, from: self.webView)
                }
            }
        }
        resourceRoot = Bundle.main.url(forResource: "CuppaCanvas", withExtension: nil)
        if resourceRoot == nil { resourceRoot = Bundle.module.url(forResource: "CuppaCanvas", withExtension: nil) }
        observation = context.observe { [weak self] in self?.scheduleReload() }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.presentSelection(completed: false) })
        }
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.endSelection(); self?.onCancelSmartTags?(nil) })
        windowObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in self?.endSelection() })
        reload()
    }
    private func scheduleReload() {
        publishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        publishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func reload() {
        window.title = "WEAVIA · " + context.project
        guard let root = resourceRoot else {
            webView.loadHTMLString("<h2>画布资源未打包</h2><p>请重新运行 build_app.sh，原项目资料未改变。</p>", baseURL: nil); return
        }
        if loadedProject != context.project {
            onCancelSmartTags?(nil)
            endSelection()
            attachmentHandler.project = context.project
            attachmentWindows.forEach { $0.close() }; attachmentWindows.removeAll()
            loadedProject = context.project; isReady = false; selectedCards = []
            var parts = URLComponents(url: root.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false)!
            parts.queryItems = [URLQueryItem(name: "project", value: context.project)]
            parts.fragment = destination
            if let url = parts.url { webView.loadFileURL(url, allowingReadAccessTo: root) }
        } else if isReady { publish() }
    }
    func show(projectHome: Bool = false) {
        destination = projectHome ? "projects" : "cuppa"
        reload()
        if isReady { webView.evaluateJavaScript("location.hash = '\(destination)'", completionHandler: nil) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func setCapturePresentation(_ active: Bool) { window.level = active ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5) : .normal }
    func setMode(_ active: Bool) { mode = active ? "cocreate" : "focus"; if !active { endSelection() }; if isReady { publish() } }
    private func endSelection() {
        if !selectionSession.isEmpty { invoke("alignSelection", ["projectId": context.project, "selectionSession": selectionSession, "visible": false]) }
        selectionSession = ""; selectionBounds = nil; selectionCards = []; onSelectionEnded?()
    }
    /// getBoundingClientRect is CSS viewport space, already including canvas zoom/pan.
    static func viewportRect(_ body: [String: Any], in bounds: NSRect) -> NSRect? {
        func number(_ key: String) -> CGFloat? {
            guard let n = body[key] as? NSNumber, n.doubleValue.isFinite else { return nil }; return CGFloat(n.doubleValue)
        }
        guard bounds.width > 0, bounds.height > 0, let x = number("x"), let y = number("y"), let w = number("width"), let h = number("height"),
              let vw = number("viewportWidth"), let vh = number("viewportHeight"), vw > 0, vh > 0, w > 0, h > 0,
              x >= 0, y >= 0, x + w <= vw + 1, y + h <= vh + 1 else { return nil }
        return NSRect(x: bounds.minX + x * bounds.width / vw, y: bounds.minY + y * bounds.height / vh,
                      width: w * bounds.width / vw, height: h * bounds.height / vh)
    }
    private func presentSelection(completed: Bool, explicit: Bool = false) {
        guard !selectionSession.isEmpty, let data = selectionBounds,
              let local = Self.viewportRect(data, in: webView.bounds), window.isVisible,
              mode == "cocreate", NSApp.isActive, (window.isKeyWindow || !completed) else { return }
        let rect = webView.isFlipped ? local : NSRect(x: local.minX, y: webView.bounds.maxY - local.maxY, width: local.width, height: local.height)
        let screen = window.convertToScreen(webView.convert(rect, to: nil))
        guard let anchor = onSelection?(screen, selectionCards, selectionSession, completed, explicit) else {
            invoke("alignSelection", ["projectId": context.project, "selectionSession": selectionSession, "visible": false]); return
        }
        let point = webView.convert(window.convertPoint(fromScreen: anchor), from: nil)
        let vw = (data["viewportWidth"] as? NSNumber)?.doubleValue ?? 1
        let vh = (data["viewportHeight"] as? NSNumber)?.doubleValue ?? 1
        invoke("alignSelection", ["projectId": context.project, "selectionSession": selectionSession, "visible": true,
            "x": (point.x - webView.bounds.minX) * vw / webView.bounds.width,
            "y": (webView.isFlipped ? point.y - webView.bounds.minY : webView.bounds.maxY - point.y) * vh / webView.bounds.height])
    }
    private func publish() {
        revision += 1
        let materials = context.materials.filter { $0.project == context.project }
        assets.register(materials, project: context.project)
        var payload: [String: Any] = ["version": 1, "revision": revision, "projectId": context.project,
            "selectionDelayMS": max(250, NSEvent.doubleClickInterval * 1000 + 30),
            "projects": context.projectNames.map { ["id": $0, "name": $0] }, "mode": mode,
            "materials": materials.map { Self.material($0, imageURL: assets.url(for: $0)) }, "storageStatus": context.storageStatus]
        do { if let value = try snapshots.load(context.project) { payload["canvasSnapshot"] = value } }
        catch { payload["storageError"] = error.localizedDescription }
        invoke("receiveSnapshot", payload)
    }
    static func material(_ item: CompanionMaterial, imageURL: URL? = nil) -> [String: Any] {
        var value: [String: Any] = ["id": item.id, "title": item.title, "text": item.text, "note": item.note,
            "saved": item.saved, "kind": item.metadata.kind, "sourceLabel": item.metadata.source,
            "sourceURL": item.metadata.sourceURL ?? "", "tags": item.metadata.acceptedSuggestions, "area": item.area]
        // Pixel bytes stay in native storage. A constrained local handler serves
        // only current-project images, keeping snapshots well below WebKit's cache quota.
        if let imageURL { value["imageURL"] = imageURL.absoluteString }
        return value
    }
    private func invoke(_ method: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.mouseCompanionMac && window.mouseCompanionMac.\(method)(\(json));", completionHandler: nil)
    }
    private func ack(_ id: String, ok: Bool = true, message: String = "", extra: [String: Any] = [:]) {
        guard let data = try? JSONSerialization.data(withJSONObject: [id]), let ids = String(data: data, encoding: .utf8) else { return }
        var body = extra; body["ok"] = ok; body["message"] = message
        guard let d = try? JSONSerialization.data(withJSONObject: body), let json = String(data: d, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.mouseCompanionMac && window.mouseCompanionMac.ack(\(ids)[0],\(json));", completionHandler: nil)
    }
    func receiveAgentResult(requestID: String, status: String, text: String, project: String) {
        guard project == context.project else { return }
        invoke("receiveAgentResult", ["requestId": requestID, "status": status, "text": text, "projectId": project])
    }
    func receiveSmartTagResult(_ payload: [String: Any]) {
        guard payload["projectId"] as? String == context.project else { return }
        invoke("receiveSmartTagResult", payload)
    }
    private func isTrusted(_ url: URL?) -> Bool {
        guard let url, url.isFileURL, let root = resourceRoot else { return false }
        return url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, isTrusted(message.frameInfo.request.url),
            let body = message.body as? [String: Any], body["version"] as? Int == 1,
            let action = body["action"] as? String else { return }
        let id = body["requestId"] as? String ?? ""
        guard action == "ready" || (body["projectId"] as? String) == context.project else {
            ack(id, ok: false, message: "项目已切换，请在当前项目重新操作。"); return
        }
        switch action {
        case "ready": isReady = true; publish(); ack(id)
        case "saveCanvas":
            guard let snapshot = body["snapshot"] as? [String: Any] else { ack(id, ok: false, message: "画布格式无效"); return }
            do { try snapshots.save(snapshot, project: context.project); ack(id, message: "画布已保存到本机", extra: ["revision": revision]) }
            catch { ack(id, ok: false, message: error.localizedDescription) }
        case "importAttachment":
            guard let kind = body["kind"] as? String, ["image", "pdf"].contains(kind), !importingAttachment else { ack(id, ok: false, message: "请选择图片或 PDF，或先完成当前选择。"); return }
            endSelection(); importingAttachment = true
            let project = context.project, panel = NSOpenPanel()
            panel.allowedContentTypes = kind == "pdf" ? [.pdf] : [.png, .jpeg, .gif, .tiff, .heic, .webP]
            panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
            panel.message = "仅将你选择的原件复制到当前项目本机目录，不上传。单个文件最多 50 MB。"
            panel.beginSheetModal(for: window) { [weak self] result in
                guard let self else { return }; self.importingAttachment = false
                guard self.context.project == project else { self.ack(id, ok: false, message: "项目已切换，未导入文件。"); return }
                guard result == .OK, let url = panel.url else { self.ack(id, extra: ["cancelled": true]); return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do { let record = try self.attachments.importFile(url, kind: kind, project: project)
                    self.ack(id, extra: ["attachment": self.attachments.payload(record, project: project)])
                } catch { self.ack(id, ok: false, message: error.localizedDescription) }
            }
        case "previewAttachment":
            guard let attachmentID = body["attachmentId"] as? String else { ack(id, ok: false); return }
            do { try previewAttachment(attachmentID, pageNumber: body["pageNumber"] as? Int ?? 1); ack(id) } catch { ack(id, ok: false, message: error.localizedDescription) }
        case "selectionEnded": endSelection(); ack(id)
        case "selectionCompleted":
            guard let session = body["selectionSession"] as? String, let bounds = body["bounds"] as? [String: Any],
                  Self.viewportRect(bounds, in: webView.bounds) != nil else { ack(id, ok: false); return }
            let cards = body["cards"] as? [[String: Any]] ?? []
            guard cards.count <= 8 else { endSelection(); ack(id, ok: false, message: "每次最多向伙伴提供 8 张卡片，请减少选择后重试。"); return }
            selectionSession = session; selectionBounds = bounds
            selectedCards = cards
            selectionCards = selectedCards
            presentSelection(completed: true, explicit: body["explicit"] as? Bool ?? false); ack(id)
        case "selectionGeometry":
            if body["selectionSession"] as? String == selectionSession, let bounds = body["bounds"] as? [String: Any], Self.viewportRect(bounds, in: webView.bounds) != nil {
                selectionBounds = bounds; presentSelection(completed: false)
            }; ack(id)
        case "selectCards": selectedCards = body["cards"] as? [[String: Any]] ?? []; ack(id)
        case "generateSmartTags":
            guard let card = body["card"] as? [String: Any], let generate = onSmartTags else { ack(id, ok: false, message: "智能标签服务尚未就绪。"); return }
            generate(card, id); ack(id)
        case "cancelSmartTags":
            if let requestID = body["tagRequestId"] as? String { onCancelSmartTags?(requestID) }
            ack(id)
        case "openAgent":
            let prompt = (body["prompt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard prompt.count <= 16000 else { ack(id, ok: false, message: "问题请控制在 16000 字以内。"); return }
            let cards = body["cards"] as? [[String: Any]] ?? selectedCards
            guard cards.count <= 8 else { ack(id, ok: false, message: "每次最多向伙伴提供 8 张卡片，请减少选择后重试。"); return }
            onAgent?(prompt, cards, id); ack(id, message: "已交给鼠标伙伴")
        case "cancelAgent": onCancelAgent?(); ack(id, message: "已中止生成")
        case "trayCommand":
            let ids = Set(body["ids"] as? [String] ?? [])
            let materials = context.materials.filter { $0.project == context.project && ids.contains($0.id) }
            if body["command"] as? String == "open", let first = materials.first {
                onOpenMaterial?(first.id); ack(id)
            } else if body["command"] as? String == "save" {
                for item in materials {
                    context.upsert(CompanionMaterial(id: item.id, project: item.project, title: item.title, text: item.text, note: item.note, area: item.area, image: item.image, saved: true, metadata: item.metadata))
                }
                publish(); ack(id, message: "已加入当前项目画布")
            } else { ack(id, ok: false, message: "未找到当前项目的托盘材料") }
        case "openURL":
            if let raw = body["url"] as? String, let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); ack(id) }
            else { ack(id, ok: false, message: "仅支持打开网页来源链接。") }
        case "switchProject", "createProject":
            let name = ((body[action == "createProject" ? "name" : "targetProjectId"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if action == "switchProject", name.isEmpty { ack(id, ok: false, message: "请选择本机项目。"); return }
            guard !name.isEmpty, name.count <= 120 else { ack(id, ok: false, message: "项目名称需为 1 至 120 字。"); return }
            destination = "cuppa"
            ack(id); onProjectSelected?(name)
        case "setWorkMode":
            let active = (body["mode"] as? String) == "cocreate"
            onWorkMode?(active); setMode(active); ack(id, extra: ["mode": mode])
        case "openSettings": onSettings?(); ack(id)
        case "openHistory": onHistory?(); ack(id)
        default: ack(id, ok: false, message: "当前 Mac 版暂不支持此操作。")
        }
    }
    private func previewAttachment(_ id: String, pageNumber: Int = 1) throws {
        let record = try attachments.load(id, project: context.project), url = try attachments.original(id, project: context.project)
        let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 700), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        preview.title = record.filename + " · 本机原件"; preview.isReleasedWhenClosed = false
        if record.kind == "pdf" {
            guard let document = PDFDocument(url: url) else { throw NSError(domain: "CanvasAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "本机 PDF 已损坏，无法预览。"] ) }
            let view = PDFView(frame: preview.contentView!.bounds); view.autoScales = true; view.displayMode = .singlePageContinuous; view.document = document; if let page = document.page(at: min(max(pageNumber, 1), max(document.pageCount, 1)) - 1) { view.go(to: page) }; preview.contentView = view
        } else {
            guard let image = NSImage(contentsOf: url) else { throw NSError(domain: "CanvasAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "本机图片已损坏，无法预览。"] ) }
            let scroll = NSScrollView(frame: preview.contentView!.bounds); scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
            scroll.allowsMagnification = true; scroll.minMagnification = 0.05; scroll.maxMagnification = 4
            let view = NSImageView(frame: NSRect(origin: .zero, size: image.size)); view.image = image; view.imageScaling = .scaleNone
            scroll.documentView = view; preview.contentView = scroll
            scroll.magnification = min(1, min(scroll.contentSize.width / max(1, image.size.width), scroll.contentSize.height / max(1, image.size.height)))
        }
        attachmentWindows.removeAll { !$0.isVisible }; attachmentWindows.append(preview)
        preview.center(); preview.makeKeyAndOrderFront(nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { /* ready is emitted after all canvas modules load. */ }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if isTrusted(url) || url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = "WEAVIA"; alert.informativeText = message; alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "确认"); alert.addButton(withTitle: "取消"); alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert(); alert.messageText = prompt; let field = NSTextField(string: defaultText ?? ""); field.frame = NSRect(x: 0, y: 0, width: 320, height: 26); alert.accessoryView = field
        alert.addButton(withTitle: "确认"); alert.addButton(withTitle: "取消"); alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
}

/// Read-only URL scheme with an explicit in-memory allowlist. No paths are read
/// from URL input, and no network request or arbitrary filesystem URL is accepted.
private final class MacWorkspaceAssetHandler: NSObject, WKURLSchemeHandler {
    private var project = ""
    private var images: [String: NSImage] = [:]
    private var data: [String: Data] = [:]
    private var identifiers: [String: String] = [:]

    func register(_ materials: [CompanionMaterial], project: String) {
        self.project = project
        images.removeAll(); data.removeAll(); identifiers.removeAll()
        for material in materials {
            guard let image = material.image else { continue }
            // Normal materials use UUIDs. Stable opaque IDs also support older imports.
            let digest = SHA256.hash(data: Data((project + "\0" + material.id).utf8))
            let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
            let chars = Array(hex)
            let key = [String(chars[0..<8]), String(chars[8..<12]), String(chars[12..<16]), String(chars[16..<20]), String(chars[20..<32])].joined(separator: "-")
            identifiers[material.id] = key; images[key] = image
        }
    }
    func url(for material: CompanionMaterial) -> URL? {
        guard let key = identifiers[material.id] else { return nil }
        var parts = URLComponents()
        parts.scheme = "weavia-asset"; parts.host = "material"; parts.path = "/" + key + ".png"
        parts.queryItems = [URLQueryItem(name: "project", value: project)]
        return parts.url
    }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "weavia-asset", parts.host == "material", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil, parts.queryItems?.count == 1,
              parts.queryItems?.first?.name == "project", parts.queryItems?.first?.value == project,
              parts.path.hasPrefix("/"), parts.path.hasSuffix(".png") else {
            task.didFailWithError(URLError(.unsupportedURL)); return
        }
        let key = String(parts.path.dropFirst().dropLast(4))
        guard UUID(uuidString: key) != nil, let image = images[key] else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        if data[key] == nil, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            data[key] = bitmap.representation(using: .png, properties: [:])
        }
        guard let png = data[key] else { task.didFailWithError(URLError(.cannotDecodeContentData)); return }
        task.didReceive(URLResponse(url: url, mimeType: "image/png", expectedContentLength: png.count, textEncodingName: nil))
        task.didReceive(png); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { /* Requests complete synchronously. */ }
}

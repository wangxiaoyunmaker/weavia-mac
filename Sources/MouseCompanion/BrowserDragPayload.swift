import AppKit

enum BrowserDragPayload {
    static func sameURL(_ a: String, _ b: String) -> Bool {
        func normalize(_ value: String) -> String? {
            guard var url = URLComponents(string: value), url.host != nil else { return nil }
            url.fragment = nil
            // Xiaohongshu's search links redirect to the same note under /explore.
            // Only these known note routes and a 24-hex note ID are equivalent.
            let host = url.host?.lowercased() ?? ""
            let parts = url.path.split(separator: "/").map(String.init)
            let id = parts.count == 2 && ["explore", "search_result"].contains(parts[0]) ? parts[1] : parts.count == 3 && parts[0] == "discovery" && parts[1] == "item" ? parts[2] : nil
            if ["xiaohongshu.com", "www.xiaohongshu.com", "m.xiaohongshu.com"].contains(host), let id, id.range(of: "^[a-fA-F0-9]{24}$", options: .regularExpression) != nil {
                return "https://www.xiaohongshu.com/explore/" + id.lowercased()
            }
            while url.path.count > 1 && url.path.hasSuffix("/") { url.path.removeLast() }
            let items = (url.queryItems ?? []).filter {
                !$0.name.lowercased().hasPrefix("utm_") && !$0.name.lowercased().hasPrefix("xsec_") && !["spm", "from", "share_source"].contains($0.name)
            }.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
            url.queryItems = items.isEmpty ? nil : items
            return url.string
        }
        guard let x = normalize(a), let y = normalize(b) else { return false }
        return x == y
    }

    static func read(_ pasteboard: NSPasteboard, target: URL) -> (title: String?, image: NSImage?) {
        var html = pasteboard.string(forType: .html)
        var resources: [[String: Any]] = []
        for name in ["Apple Web Archive pasteboard type", "com.apple.webarchive", "application/x-webarchive"] {
            guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(name)),
                  let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            if html == nil, let main = archive["WebMainResource"] as? [String: Any], let data = main["WebResourceData"] as? Data { html = String(data: data, encoding: .utf8) }
            resources = archive["WebSubresources"] as? [[String: Any]] ?? []
            break
        }
        guard let html, let document = try? XMLDocument(xmlString: html, options: .documentTidyHTML) else { return (nil, nil) }
        let anchors = (try? document.nodes(forXPath: "//a[@href]")) as? [XMLElement] ?? []
        let anchor = anchors.first { sameURL($0.attribute(forName: "href")?.stringValue ?? "", target.absoluteString) }
        let images = (try? (anchor ?? document.rootElement())?.nodes(forXPath: ".//img[@src]")) as? [XMLElement] ?? []
        let image = images.first { sameURL($0.attribute(forName: "src")?.stringValue ?? "", target.absoluteString) } ?? (anchor != nil ? images.first : nil)
        let rawTitle = anchor?.attribute(forName: "title")?.stringValue ?? anchor?.stringValue ?? image?.attribute(forName: "alt")?.stringValue
        let title = rawTitle?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let imageURL = image?.attribute(forName: "src")?.stringValue
        var preview: NSImage?
        if let imageURL, imageURL.hasPrefix("data:image/"), let split = imageURL.range(of: ";base64,"), let data = Data(base64Encoded: String(imageURL[split.upperBound...])) {
            preview = NSImage(data: data)
        } else if let imageURL, let resource = resources.first(where: { sameURL($0["WebResourceURL"] as? String ?? "", imageURL) }), let data = resource["WebResourceData"] as? Data {
            preview = NSImage(data: data)
        }
        return (title.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }, preview)
    }
}

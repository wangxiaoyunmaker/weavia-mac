import AppKit

@main
struct BrowserPayloadChecks {
    static func main() {
        let id = "6ae5696f0000000019002bbd"
        precondition(BrowserDragPayload.sameURL("https://www.xiaohongshu.com/search_result/\(id)?xsec_token=one", "https://www.xiaohongshu.com/explore/\(id)?xsec_token=two"))
        precondition(BrowserDragPayload.sameURL("https://m.xiaohongshu.com/discovery/item/\(id)", "https://www.xiaohongshu.com/explore/\(id)"))
        precondition(!BrowserDragPayload.sameURL("https://www.xiaohongshu.com/explore/\(id)", "https://www.xiaohongshu.com/explore/6ae5696f0000000019002bbe"))
        precondition(!BrowserDragPayload.sameURL("https://www.xiaohongshu.com/search_result_ai?q=\(id)", "https://www.xiaohongshu.com/explore/\(id)"))
        precondition(!BrowserDragPayload.sameURL("https://www.xiaohongshu.com.evil.invalid/explore/\(id)", "https://www.xiaohongshu.com/explore/\(id)"))
        precondition(!BrowserDragPayload.sameURL("https://fixture.invalid/search_result/\(id)", "https://fixture.invalid/explore/\(id)"))
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let target = URL(string: "https://fixture.invalid/post/selected?xsec_token=one")!
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5GkAAAAASUVORK5CYII=")!
        let html = "<a href='https://fixture.invalid/post/other'>错误标题</a><a href='https://fixture.invalid/post/selected?xsec_token=two' title='拖拽自带的真实标题'><img src='https://fixture.invalid/photo.png'></a>"
        let archive: [String: Any] = ["WebMainResource": ["WebResourceData": Data(html.utf8)], "WebSubresources": [["WebResourceURL": "https://fixture.invalid/photo.png", "WebResourceData": png]]]
        pb.setData(try! PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0), forType: NSPasteboard.PasteboardType("com.apple.webarchive"))
        let value = BrowserDragPayload.read(pb, target: target)
        precondition(value.title == "拖拽自带的真实标题" && value.image != nil)
        precondition(!BrowserDragPayload.sameURL("https://fixture.invalid/watch?v=one", "https://fixture.invalid/watch?v=two"))
        let mismatch = BrowserDragPayload.read(pb, target: URL(string: "https://fixture.invalid/post/missing")!)
        precondition(mismatch.title == nil && mismatch.image == nil)
        print("Browser drag payload checks: PASS")
    }
}

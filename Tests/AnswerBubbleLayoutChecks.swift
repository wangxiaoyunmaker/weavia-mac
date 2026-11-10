import AppKit

@main struct AnswerBubbleLayoutChecks {
    static func main() {
        let available = NSSize(width: 1280, height: 800)
        func text(_ value: String) -> NSAttributedString { NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 14)]) }
        let short = AnswerBubbleLayout.measure(text("你好。"), status: "已完成", collapsed: false, available: available)
        let medium = AnswerBubbleLayout.measure(text("这是一段会随着字数增长而自然变宽的回答。"), status: "已完成", collapsed: false, available: available)
        let long = AnswerBubbleLayout.measure(text(String(repeating: "这是一段需要换行并滚动查看的较长回答。\n", count: 100)), status: "已完成", collapsed: false, available: available)
        precondition(short.size.width < medium.size.width && short.size.height < 95)
        precondition(long.size.height == 360 && long.scrolls && long.textHeight > long.size.height)
        precondition(long.size.width <= 420)
        let folded = AnswerBubbleLayout.measure(text("折叠不丢失内容"), status: "已完成", collapsed: true, available: available)
        precondition(folded.size.height == 36 && folded.size.width <= 240)
        let loading = AnswerBubbleLayout.measure(text(""), status: "正在理解…", collapsed: false, available: available)
        precondition(loading.size.height == 36)
        let small = AnswerBubbleLayout.measure(text(String(repeating: "内容", count: 200)), status: "已完成", collapsed: false, available: NSSize(width: 300, height: 280))
        precondition(small.size.width <= 276 && small.size.height <= 232 && small.scrolls)
        print("PASS: short response is compact, width grows with text, long responses scroll within bounds, collapse/loading use a 36pt header, and small displays constrain the bubble")
    }
}

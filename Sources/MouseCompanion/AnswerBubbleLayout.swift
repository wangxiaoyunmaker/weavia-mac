import AppKit

struct AnswerBubbleLayout {
    let size: NSSize
    let textWidth: CGFloat
    let textHeight: CGFloat
    let scrolls: Bool
    static let headerHeight: CGFloat = 36
    static let horizontalPadding: CGFloat = 12

    static func measure(_ text: NSAttributedString, status: String, collapsed: Bool, available: NSSize) -> AnswerBubbleLayout {
        let maxWidth = max(180, min(420, available.width - 24))
        let statusWidth = ceil((status as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width)
        // A compact status and four 24pt actions; long status text may truncate on a small display.
        let minimum = min(maxWidth, max(220, statusWidth + 156))
        guard !collapsed, text.length > 0 else {
            return AnswerBubbleLayout(size: NSSize(width: minimum, height: headerHeight), textWidth: minimum - 24, textHeight: 0, scrolls: false)
        }
        let natural = ceil(text.boundingRect(with: NSSize(width: 10000, height: 100000), options: [.usesLineFragmentOrigin, .usesFontLeading]).width)
        let width = min(maxWidth, max(minimum, natural + horizontalPadding * 2))
        let maximumHeight = max(80, min(360, available.height - 48))
        let bodyLimit = maximumHeight - headerHeight - 12
        var textWidth = width - horizontalPadding * 2
        var height = textHeight(text, width: textWidth)
        let scrolls = height > bodyLimit
        if scrolls { textWidth -= 14; height = textHeight(text, width: textWidth) }
        return AnswerBubbleLayout(size: NSSize(width: width, height: headerHeight + 12 + min(height, bodyLimit)), textWidth: textWidth, textHeight: height, scrolls: scrolls)
    }
    private static func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, width), height: 1000000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height) + 2
    }
}

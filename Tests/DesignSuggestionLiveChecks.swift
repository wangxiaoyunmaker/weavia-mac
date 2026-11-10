import Foundation
import Security

@main
struct DesignSuggestionLiveChecks {
    static func main() {
        // Reuse the user's configured endpoint; never print or persist credentials.
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.designerworkspace.mousecompanion.prototype", kSecAttrAccount as String: "openai-api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            print("Configured credential not available to this test process"); exit(2)
        }
        let settings = UserDefaults(suiteName: "com.designerworkspace.mousecompanion.prototype")!
        let base = settings.string(forKey: "agent-api-base-url") ?? "https://api.chatanywhere.tech/v1"
        let model = settings.string(forKey: "agent-api-model") ?? "deepseek-v4.1-flash"
        let context = DesignSuggestionContext(title: "新手访谈摘录", text: "参与者第一次使用海报工具时没有发现保存按钮，经同学提醒才找到。此发现只来自一次访谈，尚未做可用性测试。", kind: "文字卡片", note: "希望探索新手引导", project: "海报工具", location: "研究摘录", memory: [])
        var done = false, passed = false
        let task = AgentTransport.suggest(baseURL: base, key: key, model: model, instructions: context.instructions, input: context.input) { result in
            switch result {
            case .success(let text):
                do {
                    let items = try context.parse(text)
                    print("LIVE suggestions: count=\(items.count), skills=\(items.map(\.skillID).joined(separator: ","))")
                    print(items.map { "\($0.label) — \($0.reason)" }.joined(separator: "\n"))
                    passed = true
                } catch { print("Result validation failed: \(error.localizedDescription)") }
            case .failure(let error): print("Request failed: \(error.localizedDescription)")
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(55)
        while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        task?.cancel()
        if !passed { exit(1) }
    }
}

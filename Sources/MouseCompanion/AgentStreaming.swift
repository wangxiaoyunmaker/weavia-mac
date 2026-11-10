import Foundation

/// Preserve empty SSE separators and decode UTF-8 only after a whole line arrives.
struct AgentStreamEvents {
    private var lineBytes = Data()
    private var previousCR = false
    private var dataLines: [String] = []
    private var eventName = ""
    private var parts: [String: String] = [:]
    private var order: [String] = []
    private(set) var text = ""
    private(set) var completed = false

    mutating func byte(_ byte: UInt8) throws -> Bool {
        if byte == 10 && previousCR { previousCR = false; return false }
        previousCR = byte == 13
        if byte == 10 || byte == 13 {
            guard let value = String(data: lineBytes, encoding: .utf8) else { throw Self.issue("回答包含无法读取的文字编码") }
            lineBytes.removeAll(keepingCapacity: true)
            return try line(value)
        }
        lineBytes.append(byte)
        guard lineBytes.count < 1_000_000 else { throw Self.issue("流式响应格式异常") }
        return false
    }

    mutating func line(_ line: String) throws -> Bool {
        if line.isEmpty {
            defer { dataLines = []; eventName = "" }
            guard !dataLines.isEmpty else { return false }
            return try event(dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix("data:") { dataLines.append(String(line.dropFirst(5)).removingOneLeadingSpace) }
        else if line.hasPrefix("event:") { eventName = String(line.dropFirst(6)).removingOneLeadingSpace }
        return false
    }
    private mutating func event(_ value: String) throws -> Bool {
        if value == "[DONE]" { completed = true; return false }
        guard let data = value.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Self.issue("无法解析流式回答") }
        let type = object["type"] as? String ?? eventName
        let before = text
        let key = "\(object["output_index"] as? Int ?? 0):\(object["content_index"] as? Int ?? 0)"
        if ["response.output_text.delta", "response.refusal.delta"].contains(type) {
            if parts[key] == nil { order.append(key) }
            parts[key, default: ""] += object["delta"] as? String ?? ""
            text = order.compactMap { parts[$0] }.joined(separator: "\n")
        } else if ["response.output_text.done", "response.refusal.done"].contains(type) {
            if parts[key] == nil { order.append(key) }
            parts[key] = object["text"] as? String ?? object["refusal"] as? String ?? parts[key] ?? ""
            text = order.compactMap { parts[$0] }.joined(separator: "\n")
        } else if type == "response.completed" {
            let response = object["response"] as? [String: Any] ?? [:]
            let final = Self.output(response)
            if !final.isEmpty { text = final }
            completed = true
        } else if ["error", "response.failed", "response.incomplete"].contains(type) {
            let response = object["response"] as? [String: Any] ?? object
            let error = response["error"] as? [String: Any] ?? object
            throw Self.issue(error["message"] as? String ?? (type == "response.incomplete" ? "回答未完成，请重试" : "生成回答时发生错误"))
        }
        return text != before
    }
    static func output(_ object: [String: Any]) -> String {
        if let text = object["output_text"] as? String { return text }
        return (object["output"] as? [[String: Any]] ?? []).flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { part -> String? in
            if part["type"] as? String == "output_text" { return part["text"] as? String }
            if part["type"] as? String == "refusal" { return part["refusal"] as? String }
            return nil
        }.joined(separator: "\n")
    }
    static func issue(_ text: String, code: Int = 502) -> NSError { NSError(domain: "MouseCompanion", code: code, userInfo: [NSLocalizedDescriptionKey: text]) }
}

private extension String {
    var removingOneLeadingSpace: String { hasPrefix(" ") ? String(dropFirst()) : self }
}

extension AgentTransport {
    /// Real incremental delivery; JSON-only compatible providers remain buffered.
    static func stream(baseURL: String, key: String, model: String, instructions: String, input: String, images: [String], onPartial: @escaping (String) -> Void, completion: @escaping (Result<String, Error>) -> Void) -> Task<Void, Never> {
        Task {
            do {
                guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/responses"), ["http", "https"].contains(url.scheme ?? "") else { throw AgentStreamEvents.issue("API Base URL 无效", code: 400) }
                var body = requestBody(model: model, instructions: instructions, input: input, images: images)
                body["stream"] = true
                var request = URLRequest(url: url)
                request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 90
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw AgentStreamEvents.issue("接口没有返回有效响应") }
                let sse = http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true
                var text = ""
                if !(200..<300).contains(http.statusCode) || !sse {
                    var data = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation(); data.append(byte)
                        guard data.count < 8_000_000 else { throw AgentStreamEvents.issue("接口响应过大") }
                    }
                    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                    guard (200..<300).contains(http.statusCode) else {
                        throw AgentStreamEvents.issue((object["error"] as? [String: Any])?["message"] as? String ?? "API 请求失败（\(http.statusCode)）", code: http.statusCode)
                    }
                    text = AgentStreamEvents.output(object)
                    if let state = object["status"] as? String, ["failed", "incomplete"].contains(state) { throw AgentStreamEvents.issue("回答未完成，请重试") }
                } else {
                    var events = AgentStreamEvents()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if try events.byte(byte) {
                            let partial = events.text
                            await MainActor.run { onPartial(partial) }
                        }
                        if events.completed { break }
                    }
                    guard events.completed else { throw AgentStreamEvents.issue("连接已中断，回答尚未生成完毕") }
                    text = events.text
                }
                try Task.checkCancellation()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentStreamEvents.issue("AI 没有返回回答，请重试") }
                let finalText = text
                await MainActor.run { completion(.success(finalText)) }
            } catch {
                if !Task.isCancelled { await MainActor.run { completion(.failure(error)) } }
            }
        }
    }
}

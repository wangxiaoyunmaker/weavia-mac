import Foundation

enum AgentTransport {
    @discardableResult
    static func suggest(baseURL: String, key: String, model: String, instructions: String, input: String, images: [String] = [], completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        func fail(_ message: String) { completion(.failure(NSError(domain: "MouseCompanion", code: 400, userInfo: [NSLocalizedDescriptionKey: message]))) }
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/responses"), ["http", "https"].contains(url.scheme ?? "") else { fail("API Base URL 无效"); return nil }
        let body = requestBody(model: model, instructions: instructions, input: input, images: images)
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { fail("无法整理素材内容"); return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<String, Error>
            do {
                if let error { throw error }
                guard let data, let http = response as? HTTPURLResponse else { throw issue("接口没有返回有效响应") }
                guard (200..<300).contains(http.statusCode) else {
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    throw NSError(domain: "MouseCompanion", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: (object?["error"] as? [String: Any])?["message"] as? String ?? "API 请求失败（\(http.statusCode)）"])
                }
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw issue("接口响应无法解析") }
                let output = object["output"] as? [[String: Any]] ?? []
                let pieces = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }
                let text = (object["output_text"] as? String ?? pieces.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    NSLog("Design suggestion response: status=%@, outputTypes=%@, incomplete=%@", object["status"] as? String ?? "unknown", String(describing: output.compactMap { $0["type"] as? String }), String(describing: object["incomplete_details"] ?? "none"))
                    throw issue("AI 没有返回建议，请重试")
                }
                result = .success(text)
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }
    static func requestBody(model: String, instructions: String, input: String, images: [String]) -> [String: Any] {
        var content: [[String: Any]] = [["type": "input_text", "text": input]]
        content += images.map { ["type": "input_image", "image_url": $0, "detail": "auto"] }
        return ["model": model, "instructions": instructions, "input": images.isEmpty ? input : [["role": "user", "content": content]] as Any, "store": false, "max_output_tokens": 4096]
    }
    private static func issue(_ message: String) -> Error { NSError(domain: "MouseCompanion", code: 502, userInfo: [NSLocalizedDescriptionKey: message]) }
}

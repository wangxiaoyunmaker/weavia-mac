import Foundation

@main struct AgentStreamChecks {
    static func main() throws {
        func check(_ value: Bool) { precondition(value) }
        var parser = AgentStreamEvents()
        func feed(_ object: [String: Any], ending: Bool = true) throws -> Bool {
            let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
            _ = try parser.line(": heartbeat")
            _ = try parser.line("event: ignored-fallback")
            _ = try parser.line("data: " + json)
            return ending ? try parser.line("") : false
        }
        check(try !feed(["type": "response.reasoning_text.delta", "delta": "private-reasoning"]))
        check(try feed(["type": "response.output_text.delta", "delta": "你好😀", "output_index": 0, "content_index": 0]))
        check(try feed(["type": "response.output_text.delta", "delta": "，设计师。", "output_index": 0, "content_index": 0]))
        precondition(parser.text == "你好😀，设计师。" && !parser.completed)
        check(try !feed(["type": "response.output_text.done", "text": "你好😀，设计师。", "output_index": 0, "content_index": 0]))
        _ = try feed(["type": "response.completed", "response": ["output_text": "你好😀，设计师。", "status": "completed"]])
        precondition(parser.completed && parser.text == "你好😀，设计师。")
        var failed = AgentStreamEvents()
        _ = try failed.line("data: {\"type\":\"response.incomplete\"}")
        do { _ = try failed.line(""); fatalError("Incomplete response passed as completed") } catch { precondition(!failed.completed) }
        var multiline = AgentStreamEvents()
        _ = try multiline.line("data: {\"type\":\"response.output_text.delta\",")
        _ = try multiline.line("data: \"delta\":\"多行\"}")
        check(try multiline.line("") && multiline.text == "多行")
        var packet = AgentStreamEvents()
        let wire = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"中文😀\"}\r\n\r\ndata: [DONE]\r\n\r\n"
        for value in wire.utf8 { _ = try packet.byte(value) }
        precondition(packet.completed && packet.text == "中文😀", "UTF-8 or CRLF framing broke across packet bytes")
        print("PASS: SSE comments, multiline data, visible text only, cumulative deltas, done de-duplication, completion and incomplete failure")
    }
}

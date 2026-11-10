import Foundation
@main struct SmartTagInputChecks {
 static func main() throws {
  let input = try CanvasSmartTagInput(card: ["id": "synthetic", "title": "海报", "text": "大标题与留白", "note": "", "existingTags": ["海报"], "project_history": "must not send"])
  let rows = try input.parse("{\"suggestions\":[{\"label\":\"#海报\",\"reason\":\"已有\"},{\"label\":\"留白\",\"reason\":\"原文提及留白\"},{\"label\":\"留白\",\"reason\":\"重复\"}]}")
  precondition(rows.count == 1 && rows[0]["label"] == "留白")
  let empty = try input.parse("```json\n{\"suggestions\":[]}\n```"); precondition(empty.isEmpty)
  for raw in ["not JSON", "{\"suggestions\":[{\"label\":\"bad\"}]}", "{\"suggestions\":[{\"label\":\"bad\",\"reason\":\"\"}]}"] {
   do { _ = try input.parse(raw); fatalError("Invalid model output accepted") } catch {}
  }
  let body = try JSONSerialization.jsonObject(with: Data(input.input(visual: false).utf8)) as! [String: Any]
  precondition(Set(body.keys) == Set(["material", "existing_tags", "input_mode"]))
  precondition(body["input_mode"] as? String == "single_card_text_only")
  precondition(!input.input(visual: false).contains("must not send"))
  precondition(input.instructions(visual: false).contains("没有图片像素"))
  precondition(input.instructions(visual: true).contains("已收到这张卡片的图片"))
  do { _ = try CanvasSmartTagInput(card: [:]); fatalError("Missing ID accepted") } catch {}
  print("PASS: smart tag input scope, JSON validation, deduplication and honest image/text instructions")
 }
}

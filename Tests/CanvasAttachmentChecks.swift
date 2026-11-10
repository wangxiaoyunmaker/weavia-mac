import AppKit
import PDFKit

@main struct CanvasAttachmentChecks {
 static func main() throws {
  func check(_ value: Bool) { precondition(value) }
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("weavia-attachment-check-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let store=CanvasAttachmentStore(directory:root.appendingPathComponent("store")), project="../项目甲"
  let image=NSImage(size:NSSize(width:180,height:100));image.lockFocus();NSColor.systemBlue.setFill();NSRect(x:0,y:0,width:180,height:100).fill();image.unlockFocus()
  let png=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
  let source=root.appendingPathComponent("测试.png");try png.write(to:source)
  let imported=try store.importFile(source,kind:"image",project:project)
  precondition(imported.kind=="image" && imported.byteCount==png.count)
  let original=try store.original(imported.id,project:project)
  check(try Data(contentsOf:original)==png)
  try FileManager.default.removeItem(at:source)
  check(try Data(contentsOf:store.original(imported.id,project:project))==png)
  let reopened=CanvasAttachmentStore(directory:store.directory)
  check(try reopened.load(imported.id,project:project).filename=="测试.png")
  check(try NSImage(data:reopened.thumbnail(imported.id,project:project)) != nil)
  do {_ = try store.load(imported.id,project:"项目乙");preconditionFailure("Cross-project read allowed")}catch{}
  do {_ = try store.original("../../outside",project:project);preconditionFailure("Traversal allowed")}catch{}
  let pdf=PDFDocument();pdf.insert(PDFPage(image:image)!,at:0);pdf.insert(PDFPage(image:image)!,at:1)
  let pdfURL=root.appendingPathComponent("fixture-paper.pdf");precondition(pdf.write(to:pdfURL))
  let paper=try store.importFile(pdfURL,kind:"pdf",project:project)
  precondition(paper.pageCount==2)
  check(try Data(contentsOf:store.original(paper.id,project:project))==Data(contentsOf:pdfURL))
  let payload=store.payload(paper,project:project);precondition(payload["pageCount"] as? Int==2);precondition((payload["previewURL"] as? String)?.hasPrefix("weavia-file://preview/")==true)
  let bad=root.appendingPathComponent("bad.pdf");try Data("not pdf".utf8).write(to:bad)
  do {_ = try store.importFile(bad,kind:"pdf",project:project);preconditionFailure("Invalid PDF accepted")}catch{}
  let empty=root.appendingPathComponent("empty.png");try Data().write(to:empty)
  do {_ = try store.importFile(empty,kind:"image",project:project);preconditionFailure("Empty image accepted")}catch{}
  do {_ = try store.importFile(pdfURL,kind:"image",project:project);preconditionFailure("Mismatched type accepted")}catch{}
  print("PASS: byte-identical local originals, restart/source deletion, thumbnails, PDF pages, project isolation, traversal, empty/corrupt/type validation")
 }
}

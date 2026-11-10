// Keep the user's original clipboard in memory, even if a child UI assertion traps.
import AppKit

let pasteboard = NSPasteboard.general
let saved = (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } }
let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
child.arguments = Array(CommandLine.arguments.dropFirst(2))
var status: Int32 = 1
do {
    try child.run()
    let deadline = Date().addingTimeInterval(65)
    while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if child.isRunning { child.terminate() }
    child.waitUntilExit(); status = child.terminationStatus
} catch { print("Unable to run UI check: \(error.localizedDescription)") }
pasteboard.clearContents()
pasteboard.writeObjects(saved.map { values -> NSPasteboardItem in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item })
exit(status)

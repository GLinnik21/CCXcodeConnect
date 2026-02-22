import Foundation
import Logging

private let logger = Logger(label: "tools")

enum GetSelectionTool {
    static func execute(editorContext: EditorContext?) -> MCPToolResult {
        logger.info("getCurrentSelection called")

        guard let snapshot = editorContext?.currentSelection() else {
            let emptyJson: JSONValue = .object([
                "text": .string(""),
                "filePath": .string(""),
                "fileUrl": .string(""),
                "selection": .object([
                    "start": .object(["line": .int(0), "character": .int(0)]),
                    "end": .object(["line": .int(0), "character": .int(0)]),
                    "isEmpty": .bool(true)
                ])
            ])
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(emptyJson), let str = String(data: data, encoding: .utf8) {
                return .text(str)
            }
            return .text("{}")
        }

        let result: JSONValue = .object([
            "text": .string(snapshot.text),
            "filePath": .string(snapshot.filePath),
            "fileUrl": .string(snapshot.fileUrl),
            "selection": .object([
                "start": .object(["line": .int(snapshot.startLine), "character": .int(snapshot.startCharacter)]),
                "end": .object(["line": .int(snapshot.endLine), "character": .int(snapshot.endCharacter)]),
                "isEmpty": .bool(snapshot.isEmpty)
            ])
        ])

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(result), let str = String(data: data, encoding: .utf8) {
            return .text(str)
        }
        return .error("Failed to encode selection")
    }
}

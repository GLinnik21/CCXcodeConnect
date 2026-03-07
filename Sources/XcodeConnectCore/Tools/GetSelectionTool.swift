import Foundation
import Logging

private let logger = Logger(label: "tools")

enum GetSelectionTool {
    static func execute(editorContext: EditorContext?) -> MCPToolResult {
        logger.info("getCurrentSelection called")

        guard let snapshot = editorContext?.currentSelection() else {
            return .json(.object([
                "success": .bool(false),
                "message": .string("No active editor found")
            ]))
        }

        return .json(.object([
            "success": .bool(true),
            "text": .string(snapshot.text),
            "filePath": .string(snapshot.filePath),
            "fileUrl": .string(snapshot.fileUrl),
            "selection": .object([
                "start": .object(["line": .int(snapshot.startLine), "character": .int(snapshot.startCharacter)]),
                "end": .object(["line": .int(snapshot.endLine), "character": .int(snapshot.endCharacter)]),
                "isEmpty": .bool(snapshot.isEmpty)
            ])
        ]))
    }
}

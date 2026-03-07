import Foundation
import Logging

private let logger = Logger(label: "tools")

enum CheckDocumentDirtyTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let filePath = arguments["filePath"]?.stringValue else {
            return .error("Missing filePath")
        }

        logger.info("checkDocumentDirty called for \(filePath)")

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Xcode"
            repeat with doc in source documents
                if path of doc is equal to "\(escapedPath)" then
                    return modified of doc
                end if
            end repeat
            return "NOT_FOUND"
        end tell
        """

        let output: String
        do {
            output = try runAppleScript(script)
        } catch {
            return .error("Failed to check document: \(error)")
        }

        if output == "NOT_FOUND" {
            return .json(.object([
                "success": .bool(false),
                "message": .string("Document not open: \(filePath)")
            ]))
        }

        let isDirty = output.lowercased() == "true"
        return .json(.object([
            "success": .bool(true),
            "filePath": .string(filePath),
            "isDirty": .bool(isDirty),
            "isUntitled": .bool(false)
        ]))
    }
}

import Foundation
import Logging

private let logger = Logger(label: "tools")

enum SaveDocumentTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let filePath = arguments["filePath"]?.stringValue else {
            return .error("Missing filePath")
        }

        logger.info("saveDocument called for \(filePath)")

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Xcode"
            repeat with doc in source documents
                if path of doc is equal to "\(escapedPath)" then
                    save doc
                    return "SAVED"
                end if
            end repeat
            return "NOT_FOUND"
        end tell
        """

        let output: String
        do {
            output = try runAppleScript(script)
        } catch {
            return .error("Failed to save document: \(error)")
        }

        if output == "NOT_FOUND" {
            return .json(.object([
                "success": .bool(false),
                "message": .string("Document not open: \(filePath)")
            ]))
        }

        return .json(.object([
            "success": .bool(true),
            "filePath": .string(filePath),
            "saved": .bool(true),
            "message": .string("Document saved successfully")
        ]))
    }
}

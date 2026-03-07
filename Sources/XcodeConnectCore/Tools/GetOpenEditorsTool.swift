import Foundation
import Logging

private let logger = Logger(label: "tools")

enum GetOpenEditorsTool {
    static func execute() async -> MCPToolResult {
        logger.info("getOpenEditors called")

        let script = """
        tell application "Xcode"
            set frontName to ""
            try
                set frontName to name of front source document
            end try
            set output to ""
            repeat with doc in source documents
                set docName to name of doc
                set docPath to path of doc
                set docModified to modified of doc
                set isActive to (docName is equal to frontName)
                set output to output & docName & "||" & docPath & "||" & docModified & "||" & isActive & linefeed
            end repeat
            return output
        end tell
        """

        let output: String
        do {
            output = try runAppleScript(script)
        } catch {
            return .error("Failed to query open editors: \(error)")
        }

        var editors: [JSONValue] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "||")
            guard parts.count >= 4 else { continue }
            let name = parts[0]
            let path = parts[1]
            let modified = parts[2].lowercased() == "true"
            let active = parts[3].lowercased() == "true"
            let uri = "file://\(path)"

            editors.append(.object([
                "uri": .string(uri),
                "path": .string(path),
                "label": .string(name),
                "isActive": .bool(active),
                "isDirty": .bool(modified)
            ]))
        }

        logger.info("getOpenEditors returning \(editors.count) editors")
        return .json(.object(["tabs": .array(editors)]))
    }
}

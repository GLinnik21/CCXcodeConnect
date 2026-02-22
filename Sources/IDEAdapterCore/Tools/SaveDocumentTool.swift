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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .error("Failed to save document: \(error)")
        }

        guard process.terminationStatus == 0 else {
            return .error("AppleScript failed with exit code \(process.terminationStatus)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .error("Failed to read AppleScript output")
        }

        if output == "NOT_FOUND" {
            return .error("Document not found in Xcode: \(filePath)")
        }

        let result: JSONValue = .object([
            "filePath": .string(filePath),
            "saved": .bool(true)
        ])
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(result), let str = String(data: data, encoding: .utf8) {
            return .text(str)
        }
        return .text("SAVED")
    }
}

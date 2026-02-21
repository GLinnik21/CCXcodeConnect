import Foundation

enum OpenFileTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let filePath = arguments["filePath"]?.stringValue else {
            return .error("Missing filePath")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xed")

        if let line = arguments["line"]?.intValue {
            process.arguments = ["--line", String(line), filePath]
        } else {
            process.arguments = [filePath]
        }

        do {
            try process.run()
            process.waitUntilExit()
            return .text("Opened \(filePath)")
        } catch {
            return .error("Failed to open file: \(error)")
        }
    }
}

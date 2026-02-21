import Foundation

enum OpenDiffTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let _ = arguments["old_file_path"]?.stringValue,
              let newContents = arguments["new_file_contents"]?.stringValue else {
            return .error("Missing old_file_path or new_file_contents")
        }

        return MCPToolResult(content: [
            MCPContent(type: "text", text: "FILE_SAVED"),
            MCPContent(type: "text", text: newContents)
        ])
    }
}

enum CloseDiffTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        .text("CLOSED")
    }

    static func closeAll() async -> MCPToolResult {
        .text("CLOSED")
    }
}

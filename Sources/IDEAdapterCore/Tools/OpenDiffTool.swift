import Foundation
import Logging

private let logger = Logger(label: "tools.diff")

enum OpenDiffTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let oldPath = arguments["old_file_path"]?.stringValue,
              let newContents = arguments["new_file_contents"]?.stringValue else {
            logger.warning("openDiff: missing required args old_file_path or new_file_contents")
            return .error("Missing old_file_path or new_file_contents")
        }

        logger.info("openDiff: path=\(oldPath) contentLen=\(newContents.count)")
        return MCPToolResult(content: [
            MCPContent(type: "text", text: "FILE_SAVED"),
            MCPContent(type: "text", text: newContents)
        ])
    }
}

enum CloseDiffTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        logger.info("closeDiff: tab=\(arguments["tab_name"]?.stringValue ?? "?")")
        return .text("CLOSED")
    }

    static func closeAll() async -> MCPToolResult {
        logger.info("closeAllDiffTabs")
        return .text("CLOSED")
    }
}

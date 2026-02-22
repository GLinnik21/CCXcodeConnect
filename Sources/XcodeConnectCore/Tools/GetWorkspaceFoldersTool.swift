import Foundation
import Logging

private let logger = Logger(label: "tools")

enum GetWorkspaceFoldersTool {
    static func execute() -> MCPToolResult {
        logger.info("getWorkspaceFolders called")

        let workspaces = WorkspaceDetector.detect()

        var folders: [JSONValue] = []
        for ws in workspaces {
            folders.append(.object([
                "name": .string(ws.name),
                "uri": .string("file://\(ws.path)"),
                "path": .string(ws.path)
            ]))
        }

        logger.info("getWorkspaceFolders returning \(folders.count) folders")

        let rootPath = workspaces.first?.path ?? ""
        let result: JSONValue = .object([
            "success": .bool(true),
            "folders": .array(folders),
            "rootPath": .string(rootPath)
        ])

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(result), let str = String(data: data, encoding: .utf8) {
            return .text(str)
        }
        return .error("Failed to encode workspace folders")
    }
}

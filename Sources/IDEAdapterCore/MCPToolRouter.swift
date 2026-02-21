import Foundation

public final class MCPToolRouter: @unchecked Sendable {
    private let bridgeClient: MCPBridgeClient
    public var tabIdentifier: String?

    private let ideTools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "openDiff",
            description: "Open a diff view comparing original file with new contents. Returns FILE_SAVED if accepted or DIFF_REJECTED if rejected.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "old_file_path": .object(["type": .string("string"), "description": .string("Path to the original file")]),
                    "new_file_contents": .object(["type": .string("string"), "description": .string("New file contents to compare")]),
                    "tab_name": .object(["type": .string("string"), "description": .string("Name for the diff tab")])
                ]),
                "required": .array([.string("old_file_path"), .string("new_file_contents")])
            ])
        ),
        MCPToolDefinition(
            name: "closeDiff",
            description: "Close a specific diff tab",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tab_name": .object(["type": .string("string"), "description": .string("Name of the diff tab to close")])
                ]),
                "required": .array([.string("tab_name")])
            ])
        ),
        MCPToolDefinition(
            name: "closeAllDiffTabs",
            description: "Close all open diff tabs",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ])
        ),
        MCPToolDefinition(
            name: "openFile",
            description: "Open a file in Xcode at an optional line number",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filePath": .object(["type": .string("string"), "description": .string("Absolute path to the file")]),
                    "line": .object(["type": .string("integer"), "description": .string("Line number to navigate to")])
                ]),
                "required": .array([.string("filePath")])
            ])
        ),
        MCPToolDefinition(
            name: "getDiagnostics",
            description: "Get current build diagnostics/issues from Xcode",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filePath": .object(["type": .string("string"), "description": .string("Optional file path to get diagnostics for")]),
                    "severity": .object(["type": .string("string"), "description": .string("Minimum severity: error, warning, or remark")])
                ])
            ])
        ),
        MCPToolDefinition(
            name: "executeCode",
            description: "Execute a Swift code snippet in the context of a source file in Xcode. Output comes from print statements. Only works with Swift files in buildable targets (apps, frameworks, libraries, CLI executables). Does NOT work with C/ObjC files or SPM packages without a built target.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "code": .object(["type": .string("string"), "description": .string("The Swift code snippet to execute")]),
                    "filePath": .object(["type": .string("string"), "description": .string("Xcode project-relative path to the Swift source file (e.g. 'ProjectName/Sources/MyFile.swift'), NOT an absolute filesystem path")])
                ]),
                "required": .array([.string("code"), .string("filePath")])
            ])
        ),
    ]

    public init(bridgeClient: MCPBridgeClient) {
        self.bridgeClient = bridgeClient
    }

    public func listTools() -> [MCPToolDefinition] {
        return ideTools
    }

    public func callTool(name: String, arguments: [String: JSONValue]) async -> MCPToolResult {
        switch name {
        case "openDiff":
            return await OpenDiffTool.execute(arguments: arguments)
        case "closeDiff":
            return await CloseDiffTool.execute(arguments: arguments)
        case "closeAllDiffTabs":
            return await CloseDiffTool.closeAll()
        case "openFile":
            return await OpenFileTool.execute(arguments: arguments)
        case "getDiagnostics":
            return await GetDiagnosticsTool.execute(arguments: arguments, bridgeClient: bridgeClient, tabIdentifier: tabIdentifier)
        case "executeCode":
            return await executeCode(arguments: arguments)
        default:
            return .error("Unknown tool: \(name)")
        }
    }

    private func executeCode(arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let tabId = tabIdentifier else {
            return .error("No Xcode workspace connected")
        }
        guard let code = arguments["code"]?.stringValue else {
            return .error("Missing code parameter")
        }

        var args: [String: JSONValue] = [
            "tabIdentifier": .string(tabId),
            "codeSnippet": .string(code),
        ]

        if let filePath = arguments["filePath"]?.stringValue {
            args["sourceFilePath"] = .string(filePath)
        }

        do {
            return try await bridgeClient.callTool(name: "ExecuteSnippet", arguments: args)
        } catch {
            return .error("Failed to execute code: \(error)")
        }
    }
}

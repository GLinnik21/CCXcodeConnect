import Foundation

enum GetDiagnosticsTool {
    static func execute(arguments: [String: JSONValue], bridgeClient: any ToolCallable, tabIdentifier: String?) async -> MCPToolResult {
        guard let tabId = tabIdentifier else {
            return .error("No Xcode workspace connected")
        }

        var args: [String: JSONValue] = ["tabIdentifier": .string(tabId)]

        if let severity = arguments["severity"]?.stringValue {
            args["severity"] = .string(severity)
        }

        if let filePath = arguments["filePath"]?.stringValue {
            args["glob"] = .string("**/\(filePath)")
        }

        do {
            return try await bridgeClient.callTool(name: "XcodeListNavigatorIssues", arguments: args)
        } catch {
            return .error("Failed to get diagnostics: \(error)")
        }
    }
}

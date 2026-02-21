import Foundation

enum GetDiagnosticsTool {
    static func execute(arguments: [String: JSONValue], bridgeClient: MCPBridgeClient, tabIdentifier: String?) async -> MCPToolResult {
        guard let tabId = tabIdentifier else {
            return .error("No Xcode workspace connected")
        }

        var args: [String: JSONValue] = ["tabIdentifier": .string(tabId)]

        if let severity = arguments["severity"]?.stringValue {
            args["severity"] = .string(severity)
        }

        if let filePath = arguments["filePath"]?.stringValue {
            args["filePath"] = .string(filePath)
            do {
                return try await bridgeClient.callTool(name: "XcodeRefreshCodeIssuesInFile", arguments: args)
            } catch {
                return .error("Failed to get diagnostics: \(error)")
            }
        } else {
            do {
                return try await bridgeClient.callTool(name: "XcodeListNavigatorIssues", arguments: args)
            } catch {
                return .error("Failed to get diagnostics: \(error)")
            }
        }
    }
}

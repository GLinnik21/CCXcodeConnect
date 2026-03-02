import Foundation
import Logging

private let logger = Logger(label: "tools.diagnostics")

enum GetDiagnosticsTool {
    static func execute(arguments: [String: JSONValue], bridgeClient: any ToolCallable, tabIdentifier: String?) async -> MCPToolResult {
        guard let tabId = tabIdentifier else {
            logger.warning("getDiagnostics: no tabIdentifier, Xcode workspace not connected")
            return .error("No Xcode workspace connected")
        }

        var args: [String: JSONValue] = ["tabIdentifier": .string(tabId)]

        if let severity = arguments["severity"]?.stringValue {
            args["severity"] = .string(severity)
            logger.debug("getDiagnostics: severity=\(severity)")
        }

        if let filePath = Self.resolveFilePath(from: arguments) {
            args["glob"] = .string("**/\(filePath)")
            logger.debug("getDiagnostics: filtering by file=\(filePath)")
        }

        logger.info("getDiagnostics: proxying to XcodeListNavigatorIssues tab=\(tabId)")
        do {
            let result = try await bridgeClient.callTool(name: "XcodeListNavigatorIssues", arguments: args)
            logger.debug("getDiagnostics: got \(result.content.count) content items, isError=\(result.isError.map(String.init) ?? "nil")")
            return result
        } catch {
            logger.error("getDiagnostics: bridge call failed: \(error)")
            return .error("Failed to get diagnostics: \(error)")
        }
    }

    static func resolveFilePath(from arguments: [String: JSONValue]) -> String? {
        if let filePath = arguments["filePath"]?.stringValue {
            return filePath
        }
        if let uri = arguments["uri"]?.stringValue {
            if uri.hasPrefix("file://") {
                return String(uri.dropFirst("file://".count))
            }
            return uri
        }
        return nil
    }
}

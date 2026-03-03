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
        }

        let filterPath = Self.resolveFilePath(from: arguments)
        if let filePath = filterPath {
            let globName = URL(fileURLWithPath: filePath).lastPathComponent
            args["glob"] = .string("**/\(globName)")
            logger.debug("getDiagnostics: filtering by file=\(filePath) glob=**/\(globName)")
        }

        logger.info("getDiagnostics: proxying to XcodeListNavigatorIssues tab=\(tabId)")
        do {
            let result = try await bridgeClient.callTool(name: "XcodeListNavigatorIssues", arguments: args)
            logger.info("getDiagnostics: got \(result.content.count) content items, isError=\(result.isError.map(String.init) ?? "nil")")

            guard let text = result.content.first?.text,
                  let data = text.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                logger.info("getDiagnostics: returning raw result (no text to transform)")
                return result
            }

            let transformed = Self.transformToLSPFormat(raw, filterUri: filterPath.map { "file://\($0)" })
            let encoded = try JSONEncoder().encode(transformed)
            let lspText = String(data: encoded, encoding: .utf8) ?? "[]"
            logger.info("getDiagnostics: transformed \(raw["issues"]?.arrayValue?.count ?? 0) issues into LSP format")
            return .text(lspText)
        } catch {
            logger.error("getDiagnostics: bridge call failed: \(error)")
            return .error("Failed to get diagnostics: \(error)")
        }
    }

    static func transformToLSPFormat(_ raw: JSONValue, filterUri: String?) -> JSONValue {
        guard let issues = raw["issues"]?.arrayValue else {
            return .array([])
        }

        var grouped: [String: [JSONValue]] = [:]

        for issue in issues {
            guard let path = issue["path"]?.stringValue,
                  let message = issue["message"]?.stringValue else {
                continue
            }

            let uri = "file://\(path)"
            let line = (issue["line"]?.intValue ?? 1) - 1
            let severity = Self.mapSeverity(issue["severity"]?.stringValue)

            let diagnostic: JSONValue = .object([
                "message": .string(message),
                "severity": .string(severity),
                "range": .object([
                    "start": .object(["line": .int(line), "character": .int(0)]),
                    "end": .object(["line": .int(line), "character": .int(0)])
                ]),
                "source": .string("Xcode")
            ])

            grouped[uri, default: []].append(diagnostic)
        }

        let result: [JSONValue] = grouped.map { uri, diagnostics in
            .object([
                "uri": .string(uri),
                "diagnostics": .array(diagnostics)
            ])
        }

        return .array(result)
    }

    static func mapSeverity(_ severity: String?) -> String {
        switch severity {
        case "error": return "Error"
        case "warning": return "Warning"
        case "remark": return "Info"
        default: return "Error"
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

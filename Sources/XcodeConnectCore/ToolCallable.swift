import Foundation

public protocol ToolCallable: Sendable {
    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult
}

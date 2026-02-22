import Foundation
import Logging

private let logger = Logger(label: "handler")

public struct MCPRequestHandler: @unchecked Sendable {
    public var toolRouter: MCPToolRouter?

    public init() {}

    public func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        switch request.method {
        case "initialize":
            let result = MCPInitializeResult(
                protocolVersion: "2024-11-05",
                capabilities: MCPCapabilities(tools: MCPToolsCapability(listChanged: true)),
                serverInfo: MCPServerInfo(name: "xcode-ide-adapter", version: "1.0.0")
            )
            guard let encoded = try? JSONEncoder().encode(result),
                  let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                return JSONRPCResponse(id: request.id, error: .internalError)
            }
            return JSONRPCResponse(id: request.id, result: jsonValue)

        case "notifications/initialized":
            return nil

        case "tools/list":
            guard let router = toolRouter else {
                return JSONRPCResponse(id: request.id, result: .object(["tools": .array([])]))
            }
            let tools = router.listTools()
            guard let encoded = try? JSONEncoder().encode(tools),
                  let jsonArray = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                return JSONRPCResponse(id: request.id, result: .object(["tools": .array([])]))
            }
            return JSONRPCResponse(id: request.id, result: .object(["tools": jsonArray]))

        case "tools/call":
            guard let router = toolRouter,
                  let params = request.params?.objectValue,
                  let name = params["name"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: .invalidParams("Missing tool name"))
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            let result = await router.callTool(name: name, arguments: arguments)
            guard let encoded = try? JSONEncoder().encode(result),
                  let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                return JSONRPCResponse(id: request.id, error: .internalError)
            }
            return JSONRPCResponse(id: request.id, result: jsonValue)

        case "prompts/list":
            return JSONRPCResponse(id: request.id, result: .object(["prompts": .array([])]))

        case "ping":
            return JSONRPCResponse(id: request.id, result: .object([:]))

        default:
            if request.id == nil || request.method.starts(with: "notifications/") {
                logger.debug("ignoring notification: \(request.method)")
                return nil
            }
            return JSONRPCResponse(id: request.id, error: .methodNotFound)
        }
    }
}

import Foundation
import Logging

private let logger = Logger(label: "handler")

public struct MCPRequestHandler: @unchecked Sendable {
    public var toolRouter: MCPToolRouter?

    public init() {}

    public func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        let idStr = request.id.map { "\($0)" } ?? "nil"

        switch request.method {
        case "initialize":
            logger.info("handle initialize id=\(idStr)")
            let result = MCPInitializeResult(
                protocolVersion: "2024-11-05",
                capabilities: MCPCapabilities(tools: MCPToolsCapability(listChanged: true)),
                serverInfo: MCPServerInfo(name: "cc-xcode-connect", version: "0.0.1")
            )
            guard let encoded = try? JSONEncoder().encode(result),
                  let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                logger.error("initialize: failed to encode result")
                return JSONRPCResponse(id: request.id, error: .internalError)
            }
            return JSONRPCResponse(id: request.id, result: jsonValue)

        case "notifications/initialized":
            logger.info("handle notifications/initialized")
            return nil

        case "tools/list":
            guard let router = toolRouter else {
                logger.warning("tools/list: no toolRouter configured, returning empty list")
                return JSONRPCResponse(id: request.id, result: .object(["tools": .array([])]))
            }
            let tools = router.listTools()
            logger.info("tools/list: returning \(tools.count) tools")
            guard let encoded = try? JSONEncoder().encode(tools),
                  let jsonArray = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                logger.error("tools/list: failed to encode tools")
                return JSONRPCResponse(id: request.id, result: .object(["tools": .array([])]))
            }
            return JSONRPCResponse(id: request.id, result: .object(["tools": jsonArray]))

        case "tools/call":
            guard let router = toolRouter,
                  let params = request.params?.objectValue,
                  let name = params["name"]?.stringValue else {
                logger.error("tools/call: missing tool name or no router, params=\(request.params.map { "\($0)" } ?? "nil")")
                return JSONRPCResponse(id: request.id, error: .invalidParams("Missing tool name"))
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            logger.info("tools/call: \(name) id=\(idStr) argKeys=[\(arguments.keys.joined(separator: ", "))]")
            let result = await router.callTool(name: name, arguments: arguments)
            if result.isError == true {
                logger.warning("tools/call \(name): returned error: \(result.content.first?.text ?? "?")")
            } else {
                logger.debug("tools/call \(name): success, \(result.content.count) content items")
            }
            guard let encoded = try? JSONEncoder().encode(result),
                  let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                logger.error("tools/call \(name): failed to encode result")
                return JSONRPCResponse(id: request.id, error: .internalError)
            }
            return JSONRPCResponse(id: request.id, result: jsonValue)

        case "prompts/list":
            logger.debug("handle prompts/list id=\(idStr)")
            return JSONRPCResponse(id: request.id, result: .object(["prompts": .array([])]))

        case "ping":
            logger.debug("handle ping id=\(idStr)")
            return JSONRPCResponse(id: request.id, result: .object([:]))

        default:
            if request.id == nil || request.method.starts(with: "notifications/") {
                logger.debug("ignoring notification: \(request.method)")
                return nil
            }
            logger.warning("unrecognized method: \(request.method) id=\(idStr)")
            return JSONRPCResponse(id: request.id, error: .methodNotFound)
        }
    }
}

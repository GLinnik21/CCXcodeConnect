import XCTest
@testable import XcodeConnectCore

final class MCPRequestHandlerTests: XCTestCase {

    func testInitializeReturnsProtocolVersion() async throws {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "initialize", params: nil, id: .int(1))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected non-nil response")
        }

        let result = try XCTUnwrap(response.result)
        XCTAssertEqual(result["protocolVersion"]?.stringValue, "2024-11-05")
        XCTAssertEqual(result["serverInfo"]?["name"]?.stringValue, "ide")
    }

    func testNotificationsInitializedReturnsNil() async {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "notifications/initialized", params: nil, id: nil)
        let response = await handler.handleRequest(request)
        XCTAssertNil(response)
    }

    func testToolsListWithoutRouterReturnsEmptyArray() async throws {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "tools/list", params: nil, id: .int(2))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected non-nil response")
        }

        let tools = response.result?["tools"]?.arrayValue
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 0)
    }

    func testToolsListWithRouterReturns9Tools() async throws {
        var handler = MCPRequestHandler()
        handler.toolRouter = MCPToolRouter(bridgeClient: MockBridgeClient())
        let request = JSONRPCRequest(method: "tools/list", params: nil, id: .int(3))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected non-nil response")
        }

        let tools = try XCTUnwrap(response.result?["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 10)
    }

    func testToolsCallMissingParamsReturnsError() async throws {
        var handler = MCPRequestHandler()
        handler.toolRouter = MCPToolRouter(bridgeClient: MockBridgeClient())
        let request = JSONRPCRequest(method: "tools/call", params: nil, id: .int(4))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected non-nil response")
        }

        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32602)
    }

    func testPromptsListReturnsEmptyArray() async throws {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "prompts/list", params: nil, id: .int(6))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected non-nil response")
        }

        let prompts = response.result?["prompts"]?.arrayValue
        XCTAssertNotNil(prompts)
        XCTAssertEqual(prompts?.count, 0)
    }

    func testPingReturnsEmptyObject() async throws {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "ping", params: nil, id: .int(7))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected non-nil response")
        }

        XCTAssertNotNil(response.result)
        XCTAssertEqual(response.result?.objectValue?.count, 0)
    }

    func testUnknownMethodWithIdReturnsError() async throws {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "unknown/method", params: nil, id: .int(8))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected non-nil response")
        }

        XCTAssertEqual(response.error?.code, -32601)
    }

    func testUnknownMethodWithoutIdReturnsNil() async {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "notifications/unknown", params: nil, id: nil)
        let response = await handler.handleRequest(request)
        XCTAssertNil(response)
    }
}

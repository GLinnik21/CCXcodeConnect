import XCTest
@testable import IDEAdapterCore

final class MockBridgeClient: ToolCallable {
    var lastCallName: String?
    var lastCallArguments: [String: JSONValue]?
    var callToolResult: MCPToolResult = .text("mock result")
    var callToolError: Error?

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        lastCallName = name
        lastCallArguments = arguments
        if let error = callToolError {
            throw error
        }
        return callToolResult
    }
}

final class MCPToolRouterTests: XCTestCase {

    private func makeRouter() -> (MCPToolRouter, MockBridgeClient) {
        let mock = MockBridgeClient()
        let router = MCPToolRouter(bridgeClient: mock)
        return (router, mock)
    }

    func testListToolsReturns9Tools() {
        let (router, _) = makeRouter()
        let tools = router.listTools()
        XCTAssertEqual(tools.count, 9)
    }

    func testEachToolHasObjectSchema() {
        let (router, _) = makeRouter()
        for tool in router.listTools() {
            let schema = tool.inputSchema?.objectValue
            XCTAssertNotNil(schema, "Tool \(tool.name) should have inputSchema")
            XCTAssertEqual(schema?["type"]?.stringValue, "object", "Tool \(tool.name) schema type should be 'object'")
        }
    }

    func testCallGetCurrentSelectionWithoutContext() async throws {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "getCurrentSelection", arguments: [:])
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertNotNil(json.objectValue)
    }

    func testCallGetDiagnosticsWithoutTabReturnsError() async {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "getDiagnostics", arguments: [:])
        XCTAssertEqual(result.isError, true)
    }

    func testCallExecuteCodeWithoutTabReturnsError() async {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "executeCode", arguments: ["code": .string("print(1)")])
        XCTAssertEqual(result.isError, true)
    }

    func testCallNonexistentToolReturnsUnknown() async {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "nonexistent", arguments: [:])
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.first?.text?.contains("Unknown tool") == true)
    }
}

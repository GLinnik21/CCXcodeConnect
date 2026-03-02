import XCTest
@testable import XcodeConnectCore

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

    func testListToolsReturns10Tools() {
        let (router, _) = makeRouter()
        let tools = router.listTools()
        XCTAssertEqual(tools.count, 10)
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

    // MARK: - getDiagnostics uri parameter

    func testGetDiagnosticsWithUri() async {
        let (router, mock) = makeRouter()
        router.tabIdentifier = "tab1"
        mock.callToolResult = .text("[]")
        _ = await router.callTool(name: "getDiagnostics", arguments: [
            "uri": .string("file:///Users/test/Project/File.swift")
        ])
        XCTAssertEqual(mock.lastCallName, "XcodeListNavigatorIssues")
        let glob = mock.lastCallArguments?["glob"]?.stringValue
        XCTAssertTrue(glob?.contains("File.swift") == true)
    }

    func testGetDiagnosticsFilePathTakesPrecedenceOverUri() async {
        let (router, mock) = makeRouter()
        router.tabIdentifier = "tab1"
        mock.callToolResult = .text("[]")
        _ = await router.callTool(name: "getDiagnostics", arguments: [
            "filePath": .string("Explicit.swift"),
            "uri": .string("file:///Users/test/Ignored.swift")
        ])
        let glob = mock.lastCallArguments?["glob"]?.stringValue
        XCTAssertTrue(glob?.contains("Explicit.swift") == true)
    }

    func testGetDiagnosticsResolveFilePathFromUri() {
        let result = GetDiagnosticsTool.resolveFilePath(from: [
            "uri": .string("file:///Users/test/Project/File.swift")
        ])
        XCTAssertEqual(result, "/Users/test/Project/File.swift")
    }

    func testGetDiagnosticsResolveFilePathPrefersFilePath() {
        let result = GetDiagnosticsTool.resolveFilePath(from: [
            "filePath": .string("/direct/path.swift"),
            "uri": .string("file:///uri/path.swift")
        ])
        XCTAssertEqual(result, "/direct/path.swift")
    }

    func testGetDiagnosticsResolveFilePathReturnsNilWhenEmpty() {
        let result = GetDiagnosticsTool.resolveFilePath(from: [:])
        XCTAssertNil(result)
    }

    // MARK: - closeAllDiffTabs

    func testCloseAllDiffTabsReturnsOK() async {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "closeAllDiffTabs", arguments: [:])
        XCTAssertNil(result.isError)
        XCTAssertEqual(result.content.first?.text, "OK")
    }

    func testCloseAllDiffTabsToolExists() {
        let (router, _) = makeRouter()
        let tools = router.listTools()
        XCTAssertTrue(tools.contains(where: { $0.name == "closeAllDiffTabs" }))
    }

    // MARK: - openFile parameters

    func testOpenFileToolSchemaIncludesStartText() {
        let (router, _) = makeRouter()
        let tool = router.listTools().first(where: { $0.name == "openFile" })!
        let properties = tool.inputSchema?["properties"]?.objectValue
        XCTAssertNotNil(properties?["startText"])
        XCTAssertNotNil(properties?["endText"])
        XCTAssertNotNil(properties?["preview"])
        XCTAssertNotNil(properties?["makeFrontmost"])
        XCTAssertNotNil(properties?["selectToEndOfLine"])
    }

    func testOpenFileFindLineContaining() {
        let tmpFile = NSTemporaryDirectory() + "test_openfile_\(UUID().uuidString).swift"
        let content = "import Foundation\nfunc hello() {\n    print(\"world\")\n}\n"
        try! content.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        XCTAssertEqual(OpenFileTool.findLine(containing: "func hello", in: tmpFile), 2)
        XCTAssertEqual(OpenFileTool.findLine(containing: "print", in: tmpFile), 3)
        XCTAssertNil(OpenFileTool.findLine(containing: "nonexistent", in: tmpFile))
    }
}

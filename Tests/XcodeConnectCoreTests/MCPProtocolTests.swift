import XCTest
@testable import XcodeConnectCore

final class MCPProtocolTests: XCTestCase {

    // MARK: - JSONRPCRequest

    func testRequestRoundTripWithIntId() throws {
        let request = JSONRPCRequest(method: "tools/list", params: nil, id: .int(42))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        XCTAssertEqual(decoded.jsonrpc, "2.0")
        XCTAssertEqual(decoded.method, "tools/list")
        XCTAssertEqual(decoded.id, .int(42))
        XCTAssertNil(decoded.params)
    }

    func testRequestRoundTripWithStringId() throws {
        let request = JSONRPCRequest(method: "initialize", params: nil, id: .string("abc"))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        XCTAssertEqual(decoded.id, .string("abc"))
    }

    func testRequestRoundTripWithParams() throws {
        let params: JSONValue = .object(["name": .string("openDiff")])
        let request = JSONRPCRequest(method: "tools/call", params: params, id: .int(1))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        XCTAssertEqual(decoded.params?["name"]?.stringValue, "openDiff")
    }

    func testRequestRoundTripWithNilId() throws {
        let request = JSONRPCRequest(method: "notifications/initialized", params: nil, id: nil)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        XCTAssertNil(decoded.id)
    }

    // MARK: - JSONRPCResponse

    func testResponseRoundTripWithResult() throws {
        let response = JSONRPCResponse(id: .int(1), result: .string("ok"))
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.result?.stringValue, "ok")
        XCTAssertNil(decoded.error)
    }

    func testResponseRoundTripWithError() throws {
        let response = JSONRPCResponse(id: .int(1), error: .methodNotFound)
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.code, -32601)
    }

    // MARK: - JSONRPCError factories

    func testMethodNotFound() {
        let err = JSONRPCError.methodNotFound
        XCTAssertEqual(err.code, -32601)
        XCTAssertEqual(err.message, "Method not found")
    }

    func testInternalError() {
        let err = JSONRPCError.internalError
        XCTAssertEqual(err.code, -32603)
        XCTAssertEqual(err.message, "Internal error")
    }

    func testInvalidParams() {
        let err = JSONRPCError.invalidParams("bad param")
        XCTAssertEqual(err.code, -32602)
        XCTAssertEqual(err.message, "bad param")
    }

    // MARK: - JSONRPCNotification

    func testNotificationRoundTrip() throws {
        let notif = JSONRPCNotification(method: "selection_changed", params: .object(["text": .string("hi")]))
        let data = try JSONEncoder().encode(notif)
        let decoded = try JSONDecoder().decode(JSONRPCNotification.self, from: data)
        XCTAssertEqual(decoded.jsonrpc, "2.0")
        XCTAssertEqual(decoded.method, "selection_changed")
        XCTAssertEqual(decoded.params?["text"]?.stringValue, "hi")
    }

    // MARK: - JSONRPCId

    func testIdIntAndStringVariants() {
        let intId = JSONRPCId.int(1)
        let strId = JSONRPCId.string("abc")
        XCTAssertNotEqual(intId, strId)
        XCTAssertEqual(intId, .int(1))
        XCTAssertEqual(strId, .string("abc"))
    }

    func testIdHashable() {
        var set = Set<JSONRPCId>()
        set.insert(.int(1))
        set.insert(.string("1"))
        set.insert(.int(1))
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - MCPToolResult factories

    func testToolResultText() {
        let result = MCPToolResult.text("hello")
        XCTAssertEqual(result.content.count, 1)
        XCTAssertEqual(result.content[0].type, "text")
        XCTAssertEqual(result.content[0].text, "hello")
        XCTAssertNil(result.isError)
    }

    func testToolResultError() {
        let result = MCPToolResult.error("bad")
        XCTAssertEqual(result.content.count, 1)
        XCTAssertEqual(result.content[0].text, "bad")
        XCTAssertEqual(result.isError, true)
    }

    // MARK: - MCPInitializeResult

    func testInitializeResultRoundTrip() throws {
        let result = MCPInitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: MCPCapabilities(tools: MCPToolsCapability(listChanged: true)),
            serverInfo: MCPServerInfo(name: "cc-xcode-connect", version: "0.0.1")
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(MCPInitializeResult.self, from: data)
        XCTAssertEqual(decoded.protocolVersion, "2024-11-05")
        XCTAssertEqual(decoded.serverInfo.name, "cc-xcode-connect")
        XCTAssertEqual(decoded.serverInfo.version, "0.0.1")
        XCTAssertEqual(decoded.capabilities.tools?.listChanged, true)
    }
}

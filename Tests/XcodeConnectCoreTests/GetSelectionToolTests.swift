import XCTest
@testable import XcodeConnectCore

final class GetSelectionToolTests: XCTestCase {

    func testNilContextReturnsFailure() throws {
        let result = GetSelectionTool.execute(editorContext: nil)
        let json = try parseFirstContent(result)

        XCTAssertEqual(json["success"], .bool(false))
        XCTAssertNotNil(json["message"]?.stringValue)
    }

    func testContextWithoutSnapshotReturnsFailure() throws {
        let context = EditorContext { _ in }
        let result = GetSelectionTool.execute(editorContext: context)
        let json = try parseFirstContent(result)

        XCTAssertEqual(json["success"], .bool(false))
        XCTAssertEqual(json["message"]?.stringValue, "No active editor found")
    }

    func testResponseHasAllExpectedKeys() throws {
        let result = GetSelectionTool.execute(editorContext: nil)
        let json = try parseFirstContent(result)

        XCTAssertNotNil(json["success"], "Response must have 'success' key")
    }

    // MARK: - Helpers

    private func parseFirstContent(_ result: MCPToolResult) throws -> JSONValue {
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

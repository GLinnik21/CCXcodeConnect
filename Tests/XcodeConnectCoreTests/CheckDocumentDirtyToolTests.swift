import XCTest
@testable import XcodeConnectCore

final class CheckDocumentDirtyToolTests: XCTestCase {

    func testMissingFilePathReturnsError() async {
        let result = await CheckDocumentDirtyTool.execute(arguments: [:])
        XCTAssertEqual(result.isError, true)
    }

    func testResponseHasSuccessKey() async throws {
        let result = await CheckDocumentDirtyTool.execute(arguments: ["filePath": .string("/nonexistent/path.swift")])

        if result.isError == true {
            return
        }

        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertNotNil(json["success"], "Response must have 'success' key instead of 'found'")
        XCTAssertNil(json["found"], "Response should not use 'found' key")
    }

    func testNotFoundResponseHasMessage() async throws {
        let result = await CheckDocumentDirtyTool.execute(arguments: ["filePath": .string("/nonexistent/path.swift")])

        if result.isError == true {
            return
        }

        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        if json["success"] == .bool(false) {
            XCTAssertNotNil(json["message"]?.stringValue, "Failed response must include 'message'")
        }
    }

    func testFoundResponseHasExpectedKeys() async throws {
        let result = await CheckDocumentDirtyTool.execute(arguments: ["filePath": .string("/nonexistent/path.swift")])

        if result.isError == true {
            return
        }

        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        if json["success"] == .bool(true) {
            XCTAssertNotNil(json["filePath"]?.stringValue)
            XCTAssertNotNil(json["isDirty"])
            XCTAssertNotNil(json["isUntitled"])
        }
    }
}

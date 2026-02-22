import XCTest
@testable import XcodeConnectCore

final class SaveDocumentToolTests: XCTestCase {

    func testMissingFilePathReturnsError() async {
        let result = await SaveDocumentTool.execute(arguments: [:])
        XCTAssertEqual(result.isError, true)
    }

    func testResponseHasExpectedKeys() async throws {
        let result = await SaveDocumentTool.execute(arguments: ["filePath": .string("/nonexistent/path.swift")])

        if result.isError == true {
            let text = try XCTUnwrap(result.content.first?.text)
            let data = text.data(using: .utf8)
            if let data, let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
                XCTAssertEqual(json["success"], .bool(false))
                XCTAssertNotNil(json["message"]?.stringValue)
            }
            return
        }

        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        if json["success"] == .bool(true) {
            XCTAssertNotNil(json["filePath"]?.stringValue)
            XCTAssertNotNil(json["saved"])
            XCTAssertNotNil(json["message"]?.stringValue)
        }
    }

    func testNotFoundReturnsSuccessFalse() async throws {
        let result = await SaveDocumentTool.execute(arguments: ["filePath": .string("/nonexistent/path.swift")])

        if result.isError == true {
            return
        }

        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(json["success"], .bool(false))
    }
}

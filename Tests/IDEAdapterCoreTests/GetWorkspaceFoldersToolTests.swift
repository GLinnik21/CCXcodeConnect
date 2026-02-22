import XCTest
@testable import IDEAdapterCore

final class GetWorkspaceFoldersToolTests: XCTestCase {

    func testResponseIsWrappedObject() throws {
        let result = GetWorkspaceFoldersTool.execute()
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertNotNil(json["success"], "Response must have 'success' key")
        XCTAssertNotNil(json["folders"], "Response must have 'folders' key")
        XCTAssertNotNil(json["rootPath"], "Response must have 'rootPath' key")
    }

    func testResponseSuccessIsTrue() throws {
        let result = GetWorkspaceFoldersTool.execute()
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(json["success"], .bool(true))
    }

    func testFoldersIsArray() throws {
        let result = GetWorkspaceFoldersTool.execute()
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertNotNil(json["folders"]?.arrayValue)
    }
}

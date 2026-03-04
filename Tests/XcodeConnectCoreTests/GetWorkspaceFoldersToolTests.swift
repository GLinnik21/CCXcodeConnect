import XCTest
@testable import XcodeConnectCore

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

    func testFoldersHaveIndexField() throws {
        let result = GetWorkspaceFoldersTool.execute()
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        if let folders = json["folders"]?.arrayValue, !folders.isEmpty {
            XCTAssertNotNil(folders[0]["index"], "Each folder must have an 'index' field")
            XCTAssertEqual(folders[0]["index"]?.intValue, 0)
        }
    }

    func testResponseHasWorkspaceFileField() throws {
        let result = GetWorkspaceFoldersTool.execute()
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertNotNil(json["workspaceFile"], "Response must have 'workspaceFile' key")
    }
}

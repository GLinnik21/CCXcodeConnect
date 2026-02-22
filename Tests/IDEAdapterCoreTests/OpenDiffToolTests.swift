import XCTest
@testable import IDEAdapterCore

final class OpenDiffToolTests: XCTestCase {

    func testValidArgsReturnFileSavedAndContents() async {
        let args: [String: JSONValue] = [
            "old_file_path": .string("/tmp/file.swift"),
            "new_file_contents": .string("new code here"),
            "tab_name": .string("diff1")
        ]
        let result = await OpenDiffTool.execute(arguments: args)
        XCTAssertNil(result.isError)
        XCTAssertEqual(result.content.count, 2)
        XCTAssertEqual(result.content[0].text, "FILE_SAVED")
        XCTAssertEqual(result.content[1].text, "new code here")
    }

    func testMissingOldFilePathReturnsError() async {
        let args: [String: JSONValue] = [
            "new_file_contents": .string("code")
        ]
        let result = await OpenDiffTool.execute(arguments: args)
        XCTAssertEqual(result.isError, true)
    }

    func testMissingNewFileContentsReturnsError() async {
        let args: [String: JSONValue] = [
            "old_file_path": .string("/tmp/file.swift")
        ]
        let result = await OpenDiffTool.execute(arguments: args)
        XCTAssertEqual(result.isError, true)
    }

    func testCloseDiffReturnsClosed() async {
        let result = await CloseDiffTool.execute(arguments: ["tab_name": .string("t")])
        XCTAssertEqual(result.content.first?.text, "CLOSED")
    }

    func testCloseAllReturnsClosed() async {
        let result = await CloseDiffTool.closeAll()
        XCTAssertEqual(result.content.first?.text, "CLOSED")
    }
}

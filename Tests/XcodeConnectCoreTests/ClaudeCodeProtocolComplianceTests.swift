import XCTest
@testable import XcodeConnectCore

final class ClaudeCodeProtocolComplianceTests: XCTestCase {

    private func makeRouter() -> (MCPToolRouter, MockBridgeClient) {
        let mock = MockBridgeClient()
        let router = MCPToolRouter(bridgeClient: mock)
        return (router, mock)
    }

    // MARK: - Server identity

    func testServerInfoNameIsIde() async {
        let handler = MCPRequestHandler()
        let request = JSONRPCRequest(method: "initialize", params: nil, id: .int(1))
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected response")
        }
        XCTAssertEqual(response.result?["serverInfo"]?["name"]?.stringValue, "ide")
    }

    func testAllToolNamesMatchClaudeCodeExpectations() {
        let (router, _) = makeRouter()
        let toolNames = Set(router.listTools().map(\.name))
        let expected: Set<String> = [
            "openFile", "getDiagnostics", "executeCode",
            "getCurrentSelection", "getLatestSelection",
            "getOpenEditors", "getWorkspaceFolders",
            "checkDocumentDirty", "saveDocument", "closeAllDiffTabs"
        ]
        XCTAssertEqual(toolNames, expected)
    }

    // MARK: - getDiagnostics URI path format

    func testDiagnosticUriUsesThreeSlashesForAbsolutePath() {
        let raw: JSONValue = .object([
            "issues": .array([
                .object([
                    "path": .string("/Users/dev/Project/File.swift"),
                    "message": .string("err"),
                    "line": .int(1),
                    "severity": .string("error")
                ])
            ])
        ])
        let result = GetDiagnosticsTool.transformToLSPFormat(raw, filterUri: nil)
        let uri = result.arrayValue?[0]["uri"]?.stringValue
        XCTAssertEqual(uri, "file:///Users/dev/Project/File.swift",
                       "Claude Code normalizeFileUri strips 'file://' prefix, so absolute path must produce three slashes")
    }

    func testDiagnosticUriPreservesFullPath() {
        let path = "/Users/glinnik/Developer/MyProject/Sources/App/ContentView.swift"
        let raw: JSONValue = .object([
            "issues": .array([
                .object([
                    "path": .string(path),
                    "message": .string("err"),
                    "line": .int(1),
                    "severity": .string("error")
                ])
            ])
        ])
        let result = GetDiagnosticsTool.transformToLSPFormat(raw, filterUri: nil)
        let uri = result.arrayValue?[0]["uri"]?.stringValue
        XCTAssertEqual(uri, "file://\(path)")
    }

    func testDiagnosticUriWithSpacesInPath() {
        let raw: JSONValue = .object([
            "issues": .array([
                .object([
                    "path": .string("/Users/dev/My Project/File.swift"),
                    "message": .string("err"),
                    "line": .int(1),
                    "severity": .string("error")
                ])
            ])
        ])
        let result = GetDiagnosticsTool.transformToLSPFormat(raw, filterUri: nil)
        let uri = result.arrayValue?[0]["uri"]?.stringValue
        XCTAssertEqual(uri, "file:///Users/dev/My Project/File.swift")
    }

    // MARK: - getDiagnostics resolveFilePath strips file:// correctly

    func testResolveFilePathStripsFileProtocol() {
        let result = GetDiagnosticsTool.resolveFilePath(from: [
            "uri": .string("file:///Users/test/Project/File.swift")
        ])
        XCTAssertEqual(result, "/Users/test/Project/File.swift",
                       "Must strip exactly 'file://' to preserve leading slash")
    }

    func testResolveFilePathFromUriWithSpaces() {
        let result = GetDiagnosticsTool.resolveFilePath(from: [
            "uri": .string("file:///Users/test/My Project/File.swift")
        ])
        XCTAssertEqual(result, "/Users/test/My Project/File.swift")
    }

    func testResolveFilePathPrefersFilePathOverUri() {
        let result = GetDiagnosticsTool.resolveFilePath(from: [
            "filePath": .string("/direct/path.swift"),
            "uri": .string("file:///uri/path.swift")
        ])
        XCTAssertEqual(result, "/direct/path.swift")
    }

    func testResolveFilePathReturnsNilForEmptyArgs() {
        XCTAssertNil(GetDiagnosticsTool.resolveFilePath(from: [:]))
    }

    func testResolveFilePathPassesNonFileUri() {
        let result = GetDiagnosticsTool.resolveFilePath(from: [
            "uri": .string("/plain/path.swift")
        ])
        XCTAssertEqual(result, "/plain/path.swift")
    }

    // MARK: - getDiagnostics glob from URI path

    func testGetDiagnosticsExtractsFilenameForGlob() async {
        let (router, mock) = makeRouter()
        router.tabIdentifier = "tab1"
        mock.callToolResult = .text("{\"issues\":[]}")

        _ = await router.callTool(name: "getDiagnostics", arguments: [
            "uri": .string("file:///Users/dev/Project/Sources/ContentView.swift")
        ])

        XCTAssertEqual(mock.lastCallArguments?["glob"]?.stringValue, "**/ContentView.swift",
                       "Must use **/filename.swift glob, not full path (mcpbridge double-slash bug)")
    }

    func testGetDiagnosticsNoGlobWhenNoFilter() async {
        let (router, mock) = makeRouter()
        router.tabIdentifier = "tab1"
        mock.callToolResult = .text("{\"issues\":[]}")

        _ = await router.callTool(name: "getDiagnostics", arguments: [:])

        XCTAssertNil(mock.lastCallArguments?["glob"],
                     "Empty args = all diagnostics, no glob filter")
    }

    // MARK: - getDiagnostics full response decodable by Claude Code

    func testGetDiagnosticsResponseDecodableAsClaudeCodeDTO() async throws {
        let (router, mock) = makeRouter()
        router.tabIdentifier = "tab1"

        let bridgeResponse: JSONValue = .object([
            "issues": .array([
                .object([
                    "path": .string("/Users/dev/App/Main.swift"),
                    "message": .string("Type mismatch"),
                    "line": .int(42),
                    "severity": .string("error")
                ]),
                .object([
                    "path": .string("/Users/dev/App/Main.swift"),
                    "message": .string("Unused variable"),
                    "line": .int(10),
                    "severity": .string("warning")
                ]),
                .object([
                    "path": .string("/Users/dev/App/Helper.swift"),
                    "message": .string("Deprecated API"),
                    "line": .int(5),
                    "severity": .string("remark")
                ])
            ])
        ])
        let encoded = try JSONEncoder().encode(bridgeResponse)
        mock.callToolResult = .text(String(data: encoded, encoding: .utf8)!)

        let result = await router.callTool(name: "getDiagnostics", arguments: [:])
        let text = try XCTUnwrap(result.content.first?.text)
        let data = try XCTUnwrap(text.data(using: String.Encoding.utf8))
        let files = try JSONDecoder().decode([DiagnosticFileDTO].self, from: data)

        let mainFile = files.first(where: { $0.uri == "file:///Users/dev/App/Main.swift" })
        let helperFile = files.first(where: { $0.uri == "file:///Users/dev/App/Helper.swift" })

        XCTAssertNotNil(mainFile)
        XCTAssertEqual(mainFile?.diagnostics.count, 2)
        XCTAssertEqual(mainFile?.diagnostics.first(where: { $0.severity == "Error" })?.range.start.line, 41)
        XCTAssertEqual(mainFile?.diagnostics.first(where: { $0.severity == "Warning" })?.range.start.line, 9)

        XCTAssertNotNil(helperFile)
        XCTAssertEqual(helperFile?.diagnostics.count, 1)
        XCTAssertEqual(helperFile?.diagnostics[0].severity, "Info")
        XCTAssertEqual(helperFile?.diagnostics[0].range.start.line, 4)
        XCTAssertEqual(helperFile?.diagnostics[0].source, "Xcode")
    }

    // MARK: - getDiagnostics line indexing

    func testDiagnosticLineIsZeroIndexed() {
        let raw: JSONValue = .object([
            "issues": .array([
                .object(["path": .string("/t.swift"), "message": .string("e"), "line": .int(1), "severity": .string("error")])
            ])
        ])
        let result = GetDiagnosticsTool.transformToLSPFormat(raw, filterUri: nil)
        let line = result.arrayValue?[0]["diagnostics"]?.arrayValue?[0]["range"]?["start"]?["line"]?.intValue
        XCTAssertEqual(line, 0, "Xcode line 1 → protocol line 0")
    }

    func testDiagnosticMissingLineDefaultsToZero() {
        let raw: JSONValue = .object([
            "issues": .array([
                .object(["path": .string("/t.swift"), "message": .string("e"), "severity": .string("error")])
            ])
        ])
        let result = GetDiagnosticsTool.transformToLSPFormat(raw, filterUri: nil)
        let line = result.arrayValue?[0]["diagnostics"]?.arrayValue?[0]["range"]?["start"]?["line"]?.intValue
        XCTAssertEqual(line, 0)
    }

    // MARK: - getDiagnostics severity

    func testSeverityMappingMatchesClaudeCodeDiagnosticType() {
        XCTAssertEqual(GetDiagnosticsTool.mapSeverity("error"), "Error")
        XCTAssertEqual(GetDiagnosticsTool.mapSeverity("warning"), "Warning")
        XCTAssertEqual(GetDiagnosticsTool.mapSeverity("remark"), "Info")
        XCTAssertEqual(GetDiagnosticsTool.mapSeverity(nil), "Error")
    }

    // MARK: - getDiagnostics skips malformed issues

    func testDiagnosticSkipsIssuesWithoutPath() {
        let raw: JSONValue = .object([
            "issues": .array([
                .object(["message": .string("no path"), "line": .int(1), "severity": .string("error")]),
                .object(["path": .string("/ok.swift"), "message": .string("ok"), "line": .int(1), "severity": .string("error")])
            ])
        ])
        let result = GetDiagnosticsTool.transformToLSPFormat(raw, filterUri: nil)
        XCTAssertEqual(result.arrayValue?.count, 1)
    }

    func testDiagnosticSkipsIssuesWithoutMessage() {
        let raw: JSONValue = .object([
            "issues": .array([
                .object(["path": .string("/t.swift"), "line": .int(1), "severity": .string("error")])
            ])
        ])
        let result = GetDiagnosticsTool.transformToLSPFormat(raw, filterUri: nil)
        XCTAssertEqual(result.arrayValue?.count, 0)
    }

    // MARK: - Workspace folder paths in lock file

    func testLockFileWritesPlainAbsolutePaths() throws {
        let dir = NSTemporaryDirectory() + "locktest_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let lockPath = "\(dir)/99999.lock"
        let folders = ["/Users/dev/MyProject", "/Users/dev/OtherProject"]

        let lock: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "workspaceFolders": folders,
            "ideName": "Xcode",
            "transport": "ws",
            "runningInWindows": false,
            "authToken": "test"
        ]
        let data = try JSONSerialization.data(withJSONObject: lock)
        FileManager.default.createFile(atPath: lockPath, contents: data)

        let readData = try XCTUnwrap(FileManager.default.contents(atPath: lockPath))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: readData) as? [String: Any])
        let readFolders = try XCTUnwrap(json["workspaceFolders"] as? [String])

        for folder in readFolders {
            XCTAssertFalse(folder.hasPrefix("file://"), "Lock file paths must be plain, not file:// URIs")
            XCTAssertTrue(folder.hasPrefix("/"), "Lock file paths must be absolute")
            XCTAssertFalse(folder.hasSuffix("/"), "Lock file paths should not have trailing slash")
        }
    }

    // MARK: - Workspace path extraction from Xcode paths

    func testWorkspacePathFromXcodeproj() {
        let url = URL(fileURLWithPath: "/Users/dev/MyProject/MyProject.xcodeproj")
        let folder = url.deletingLastPathComponent().path
        XCTAssertEqual(folder, "/Users/dev/MyProject")
        XCTAssertFalse(folder.hasSuffix("/"))
    }

    func testWorkspacePathFromXcworkspace() {
        let url = URL(fileURLWithPath: "/Users/dev/MyProject/MyProject.xcworkspace")
        let folder = url.deletingLastPathComponent().path
        XCTAssertEqual(folder, "/Users/dev/MyProject")
    }

    func testWorkspacePathWithSpaces() {
        let url = URL(fileURLWithPath: "/Users/dev/My Project/App.xcodeproj")
        let folder = url.deletingLastPathComponent().path
        XCTAssertEqual(folder, "/Users/dev/My Project")
    }

    // MARK: - getWorkspaceFolders response format

    func testGetWorkspaceFoldersPathFieldIsPlainAbsolute() {
        let result = GetWorkspaceFoldersTool.execute()
        let text = result.content.first?.text ?? ""
        guard let data = text.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return
        }
        if let folders = json["folders"]?.arrayValue {
            for folder in folders {
                if let path = folder["path"]?.stringValue {
                    XCTAssertTrue(path.hasPrefix("/"), "path field must be absolute")
                    XCTAssertFalse(path.hasPrefix("file://"), "path field must be plain")
                }
                if let uri = folder["uri"]?.stringValue {
                    XCTAssertTrue(uri.hasPrefix("file://"), "uri field must have file:// protocol")
                }
            }
        }
        XCTAssertEqual(json["success"], .bool(true))
    }

    // MARK: - selection_changed notification path format

    func testSelectionNotificationFilePathIsAbsolute() {
        let notification = JSONRPCNotification(
            method: "selection_changed",
            params: .object([
                "text": .string(""),
                "filePath": .string("/Users/dev/Project/File.swift"),
                "fileUrl": .string("file:///Users/dev/Project/File.swift"),
                "selection": .object([
                    "start": .object(["line": .int(0), "character": .int(0)]),
                    "end": .object(["line": .int(0), "character": .int(0)]),
                    "isEmpty": .bool(true)
                ])
            ])
        )
        let filePath = notification.params?["filePath"]?.stringValue
        XCTAssertTrue(filePath?.hasPrefix("/") == true, "filePath in notification must be plain absolute path")
        XCTAssertFalse(filePath?.hasPrefix("file://") == true, "filePath must not have file:// prefix")
    }

    // MARK: - openFile path handling

    func testOpenFileRequiresFilePath() {
        let (router, _) = makeRouter()
        let tool = router.listTools().first(where: { $0.name == "openFile" })!
        let required = tool.inputSchema?["required"]?.arrayValue?.compactMap(\.stringValue)
        XCTAssertEqual(required, ["filePath"])
    }

    func testOpenFileMissingPathReturnsError() async {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "openFile", arguments: [:])
        XCTAssertEqual(result.isError, true)
    }

    func testOpenFileSchemaAcceptsAllClaudeCodeParams() {
        let (router, _) = makeRouter()
        let tool = router.listTools().first(where: { $0.name == "openFile" })!
        let props = tool.inputSchema?["properties"]?.objectValue
        for param in ["filePath", "preview", "startText", "endText", "selectToEndOfLine", "makeFrontmost"] {
            XCTAssertNotNil(props?[param], "openFile must accept '\(param)'")
        }
    }

    // MARK: - openDiff / close_tab graceful errors

    func testOpenDiffReturnsUnknownToolError() async {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "openDiff", arguments: [
            "old_file_path": .string("/t.swift"),
            "new_file_path": .string("/t.swift"),
            "new_file_contents": .string(""),
            "tab_name": .string("tab")
        ])
        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.first?.text?.contains("Unknown tool") == true)
    }

    func testCloseTabReturnsUnknownToolError() async {
        let (router, _) = makeRouter()
        let result = await router.callTool(name: "close_tab", arguments: [
            "tab_name": .string("tab")
        ])
        XCTAssertEqual(result.isError, true)
    }

    // MARK: - executeCode path is project-relative

    func testExecuteCodePassesRelativePath() async {
        let (router, mock) = makeRouter()
        router.tabIdentifier = "tab1"
        mock.callToolResult = .text("ok")

        _ = await router.callTool(name: "executeCode", arguments: [
            "code": .string("print(1)"),
            "filePath": .string("MyApp/Sources/main.swift")
        ])

        XCTAssertEqual(mock.lastCallName, "ExecuteSnippet")
        XCTAssertEqual(mock.lastCallArguments?["sourceFilePath"]?.stringValue, "MyApp/Sources/main.swift",
                       "executeCode filePath is project-relative, passed through to mcpbridge as-is")
    }

    // MARK: - tools/call MCP response wrapping

    func testToolsCallResponseHasContentArray() async {
        var handler = MCPRequestHandler()
        handler.toolRouter = MCPToolRouter(bridgeClient: MockBridgeClient())
        let request = JSONRPCRequest(
            method: "tools/call",
            params: .object(["name": .string("closeAllDiffTabs"), "arguments": .object([:])]),
            id: .int(1)
        )
        guard let response = await handler.handleRequest(request) else {
            return XCTFail("Expected response")
        }
        let content = response.result?["content"]?.arrayValue
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.first?["type"]?.stringValue, "text")
    }
}

// MARK: - DTOs matching Claude Code diagnosticTracking.ts interfaces

private struct DiagnosticFileDTO: Decodable {
    let uri: String
    let diagnostics: [DiagnosticDTO]
}

private struct DiagnosticDTO: Decodable {
    let message: String
    let severity: String
    let range: RangeDTO
    let source: String?
    let code: String?
}

private struct RangeDTO: Decodable {
    let start: PositionDTO
    let end: PositionDTO
}

private struct PositionDTO: Decodable {
    let line: Int
    let character: Int
}

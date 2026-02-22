import XCTest
@testable import XcodeConnectCore

final class LockFileManagerTests: XCTestCase {

    private var testDir: String!

    override func setUp() {
        super.setUp()
        testDir = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/ide"
    }

    func testWriteCreatesFileWithExpectedJSON() throws {
        let port = Int.random(in: 50000...59999)
        let token = UUID().uuidString
        let manager = LockFileManager(port: port, authToken: token)
        manager.write(workspaceFolders: ["/Users/test/project"])

        let lockPath = "\(testDir!)/\(port).lock"
        let data = try Data(contentsOf: URL(fileURLWithPath: lockPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["ideName"] as? String, "Xcode")
        XCTAssertEqual(json["transport"] as? String, "ws")
        XCTAssertEqual(json["authToken"] as? String, token)
        XCTAssertEqual(json["pid"] as? Int32, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(json["workspaceFolders"] as? [String], ["/Users/test/project"])

        manager.remove()
    }

    func testRemoveDeletesFile() {
        let port = Int.random(in: 50000...59999)
        let manager = LockFileManager(port: port, authToken: "tok")
        manager.write(workspaceFolders: [])

        let lockPath = "\(testDir!)/\(port).lock"
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockPath))

        manager.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockPath))
    }

    func testDeinitRemovesFile() {
        let port = Int.random(in: 50000...59999)
        let lockPath = "\(testDir!)/\(port).lock"

        autoreleasepool {
            let manager = LockFileManager(port: port, authToken: "tok")
            manager.write(workspaceFolders: [])
            XCTAssertTrue(FileManager.default.fileExists(atPath: lockPath))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: lockPath))
    }

    func testEmptyWorkspaceFolders() throws {
        let port = Int.random(in: 50000...59999)
        let manager = LockFileManager(port: port, authToken: "tok")
        manager.write(workspaceFolders: [])

        let lockPath = "\(testDir!)/\(port).lock"
        let data = try Data(contentsOf: URL(fileURLWithPath: lockPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["workspaceFolders"] as? [String], [])

        manager.remove()
    }

    func testMultipleWorkspaceFolders() throws {
        let port = Int.random(in: 50000...59999)
        let manager = LockFileManager(port: port, authToken: "tok")
        let folders = ["/Users/test/a", "/Users/test/b"]
        manager.write(workspaceFolders: folders)

        let lockPath = "\(testDir!)/\(port).lock"
        let data = try Data(contentsOf: URL(fileURLWithPath: lockPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["workspaceFolders"] as? [String], folders)

        manager.remove()
    }

    func testPermissions() throws {
        let port = Int.random(in: 50000...59999)
        let manager = LockFileManager(port: port, authToken: "tok")
        manager.write(workspaceFolders: [])

        let lockPath = "\(testDir!)/\(port).lock"
        let attrs = try FileManager.default.attributesOfItem(atPath: lockPath)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        XCTAssertEqual(perms, 0o600)

        manager.remove()
    }
}

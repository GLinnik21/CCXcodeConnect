import Foundation

final class LockFileManager {
    private let port: Int
    private let authToken: String
    private let lockFilePath: String

    init(port: Int, authToken: String) {
        self.port = port
        self.authToken = authToken

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.claude/ide"
        self.lockFilePath = "\(dir)/\(port).lock"

        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        chmod(dir, 0o700)

        Self.cleanStaleLocks(in: dir)
    }

    private static func cleanStaleLocks(in dir: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }
        let myPid = ProcessInfo.processInfo.processIdentifier

        for file in files where file.hasSuffix(".lock") {
            let path = "\(dir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int32,
                  json["ideName"] as? String == "Xcode",
                  pid != myPid else { continue }

            if kill(pid, 0) != 0 {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    func write(workspaceFolders: [String]) {
        let lock: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "workspaceFolders": workspaceFolders,
            "ideName": "Xcode",
            "transport": "ws",
            "runningInWindows": false,
            "authToken": authToken
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: lock, options: [.sortedKeys]) else { return }
        FileManager.default.createFile(atPath: lockFilePath, contents: data)
        chmod(lockFilePath, 0o600)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: lockFilePath)
    }

    deinit {
        remove()
    }
}

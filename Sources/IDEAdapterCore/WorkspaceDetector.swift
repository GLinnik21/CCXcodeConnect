import Foundation

public struct WorkspaceInfo {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum WorkspaceDetector {
    public static func detect() -> [WorkspaceInfo] {
        let script = "tell application \"Xcode\" to return path of every workspace document"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return [] }

        return output.components(separatedBy: ", ").compactMap { path in
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let url = URL(fileURLWithPath: trimmed)
            let name = url.lastPathComponent
            let folder = url.deletingLastPathComponent().path
            return WorkspaceInfo(name: name, path: folder)
        }
    }
}

import Foundation
import Logging

private let logger = Logger(label: "workspace")

public struct WorkspaceInfo {
    public let name: String
    public let path: String
    public let windowName: String

    public init(name: String, path: String, windowName: String) {
        self.name = name
        self.path = path
        self.windowName = windowName
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
            logger.error("workspace detect: failed to run osascript: \(error)")
            return []
        }

        guard process.terminationStatus == 0 else {
            logger.debug("workspace detect: osascript exited with \(process.terminationStatus)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return [] }

        let projectExtensions: Set<String> = ["xcodeproj", "xcworkspace", "playground"]
        let results = output.components(separatedBy: ", ").compactMap { path -> WorkspaceInfo? in
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let url = URL(fileURLWithPath: trimmed)
            let ext = url.pathExtension.lowercased()
            let folder: String
            let name: String
            let windowName: String
            if projectExtensions.contains(ext) {
                folder = url.deletingLastPathComponent().path
                name = URL(fileURLWithPath: folder).lastPathComponent
                windowName = url.deletingPathExtension().lastPathComponent
            } else {
                folder = url.path
                name = url.lastPathComponent
                windowName = name
            }
            return WorkspaceInfo(name: name, path: folder, windowName: windowName)
        }
        logger.debug("workspace detect: found \(results.count) workspaces: \(results.map(\.name).joined(separator: ", "))")
        return results
    }
}

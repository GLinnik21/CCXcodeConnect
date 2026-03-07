import Foundation

enum AppleScriptError: Error, LocalizedError {
    case nonZeroExit(Int32)

    var errorDescription: String? {
        if case .nonZeroExit(let code) = self { return "AppleScript exited with code \(code)" }
        return nil
    }
}

func runAppleScript(_ script: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw AppleScriptError.nonZeroExit(process.terminationStatus)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

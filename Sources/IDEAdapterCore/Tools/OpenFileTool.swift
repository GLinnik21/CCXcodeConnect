import Foundation
import Logging

private let logger = Logger(label: "tools.openfile")

enum OpenFileTool {
    static func execute(arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let filePath = arguments["filePath"]?.stringValue else {
            logger.warning("openFile: missing filePath arg")
            return .error("Missing filePath")
        }

        let line = arguments["line"]?.intValue
        logger.info("openFile: path=\(filePath) line=\(line.map(String.init) ?? "nil")")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xed")

        if let line {
            process.arguments = ["--line", String(line), filePath]
        } else {
            process.arguments = [filePath]
        }

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                logger.error("openFile: xed exited with code \(process.terminationStatus)")
                return .error("xed failed with exit code \(process.terminationStatus)")
            }
            logger.debug("openFile: success")
            return .text("Opened \(filePath)")
        } catch {
            logger.error("openFile: failed to run xed: \(error)")
            return .error("Failed to open file: \(error)")
        }
    }
}

import Foundation

final class EditorContext: @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private let sendNotification: (JSONRPCNotification) -> Void
    private var lastFilePath: String?
    private var lastSelectionStart: Int?
    private var lastSelectionEnd: Int?

    init(sendNotification: @escaping (JSONRPCNotification) -> Void) {
        self.sendNotification = sendNotification
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard let (filePath, rangeStart, rangeEnd) = queryXcode() else { return }

        if filePath == lastFilePath && rangeStart == lastSelectionStart && rangeEnd == lastSelectionEnd {
            return
        }

        lastFilePath = filePath
        lastSelectionStart = rangeStart
        lastSelectionEnd = rangeEnd

        guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

        let (startLine, startChar) = offsetToLineChar(in: fileContents, offset: rangeStart)
        let (endLine, endChar) = offsetToLineChar(in: fileContents, offset: rangeEnd)
        let isEmpty = rangeStart == rangeEnd

        let selectedText: String
        if !isEmpty {
            let clampedStart = max(0, min(rangeStart - 1, fileContents.count))
            let clampedEnd = max(clampedStart, min(rangeEnd - 1, fileContents.count))
            let startIdx = fileContents.index(fileContents.startIndex, offsetBy: clampedStart)
            let endIdx = fileContents.index(fileContents.startIndex, offsetBy: clampedEnd)
            selectedText = String(fileContents[startIdx..<endIdx])
        } else {
            selectedText = ""
        }

        let fileUrl = "file://\(filePath)"

        let params: JSONValue = .object([
            "text": .string(selectedText),
            "filePath": .string(filePath),
            "fileUrl": .string(fileUrl),
            "selection": .object([
                "start": .object([
                    "line": .int(startLine),
                    "character": .int(startChar)
                ]),
                "end": .object([
                    "line": .int(endLine),
                    "character": .int(endChar)
                ]),
                "isEmpty": .bool(isEmpty)
            ])
        ])

        let notification = JSONRPCNotification(method: "selection_changed", params: params)
        sendNotification(notification)
    }

    private func queryXcode() -> (String, Int, Int)? {
        let script = """
        tell application "Xcode"
            set doc to front source document
            set docPath to path of doc
            set selRange to selected character range of front source document
            set rangeStart to first item of selRange
            set rangeEnd to last item of selRange
            return docPath & "||" & rangeStart & "||" & rangeEnd
        end tell
        """

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
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }

        let parts = output.components(separatedBy: "||")
        guard parts.count == 3,
              let start = Int(parts[1]),
              let end = Int(parts[2]) else { return nil }

        return (parts[0], start, end)
    }

    private func offsetToLineChar(in text: String, offset: Int) -> (Int, Int) {
        guard offset > 0 else { return (0, 0) }

        var line = 0
        var charInLine = 0
        var currentOffset = 1

        for char in text {
            if currentOffset >= offset { break }
            if char == "\n" {
                line += 1
                charInLine = 0
            } else {
                charInLine += 1
            }
            currentOffset += 1
        }

        return (line, charInLine)
    }
}

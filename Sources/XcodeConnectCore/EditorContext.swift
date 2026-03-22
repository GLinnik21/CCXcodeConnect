import Foundation
import Logging

private let logger = Logger(label: "editor")

public struct SelectionSnapshot: Sendable {
    public let text: String
    public let filePath: String
    public let fileUrl: String
    public let startLine: Int
    public let startCharacter: Int
    public let endLine: Int
    public let endCharacter: Int
    public let isEmpty: Bool
}

public final class EditorContext: @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private let sendNotification: (JSONRPCNotification) -> Void
    private let workspaceName: String?
    private var lastFilePath: String?
    private var lastSelectionStart: Int?
    private var lastSelectionEnd: Int?
    private let snapshotLock = NSLock()
    private var _lastSnapshot: SelectionSnapshot?

    public func currentSelection() -> SelectionSnapshot? {
        snapshotLock.withLock { _lastSnapshot }
    }

    private let settings: AdapterSettingsProviding

    public init(settings: AdapterSettingsProviding, workspaceName: String? = nil, sendNotification: @escaping (JSONRPCNotification) -> Void) {
        self.settings = settings
        self.workspaceName = workspaceName
        self.sendNotification = sendNotification
    }

    public func start() {
        let ms = Int(settings.editorPollingInterval * 1000)
        logger.info("editor context polling started (\(ms)ms)")
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(ms))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        logger.info("editor context polling stopped")
        timer?.cancel()
        timer = nil
    }

    public func restart() {
        stop()
        start()
    }

    private func poll() {
        guard let (filePath, rangeStart, rangeEnd, windowWorkspace) = queryXcode() else { return }

        if let workspaceName, windowWorkspace != workspaceName {
            return
        }

        if filePath == lastFilePath && rangeStart == lastSelectionStart && rangeEnd == lastSelectionEnd {
            return
        }

        guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            logger.warning("poll: failed to read file \(filePath)")
            return
        }

        lastFilePath = filePath
        lastSelectionStart = rangeStart
        lastSelectionEnd = rangeEnd

        let ((startLine, startChar), (endLine, endChar)) = TextOffsetConverter.twoOffsetsToLineChars(in: fileContents, first: rangeStart, second: rangeEnd)
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

        snapshotLock.withLock {
            _lastSnapshot = SelectionSnapshot(
                text: selectedText,
                filePath: filePath,
                fileUrl: fileUrl,
                startLine: startLine,
                startCharacter: startChar,
                endLine: endLine,
                endCharacter: endChar,
                isEmpty: isEmpty
            )
        }

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

        logger.info("selection_changed \(filePath):\(startLine):\(startChar)-\(endLine):\(endChar) isEmpty=\(isEmpty)")
        let notification = JSONRPCNotification(method: "selection_changed", params: params)
        sendNotification(notification)
    }

    private func queryXcode() -> (String, Int, Int, String)? {
        let script = """
        tell application "Xcode"

            if not (exists front window) then
                return "NO_WINDOW"
            end if

            set winName to name of front window

            -- Extract workspace name and filename from window title
            set AppleScript's text item delimiters to " — "
            set parts to text items of winName

            if (count of parts) < 2 then
                return "NO_FILE"
            end if

            set wsName to item 1 of parts
            set filePart to item 2 of parts
            set AppleScript's text item delimiters to ", "
            set fileName to item 1 of (text items of filePart)

            set activeDoc to missing value

            repeat with d in every source document
                if name of d is fileName then
                    set activeDoc to d
                    exit repeat
                end if
            end repeat

            if activeDoc is missing value then
                return "NO_FILE"
            end if

            set docPath to path of activeDoc

            set rangeStart to 0
            set rangeEnd to 0

            try
                set selRange to selected character range of activeDoc
                if selRange is not {} then
                    set rangeStart to item 1 of selRange
                    set rangeEnd to item 2 of selRange
                end if
            end try

            return docPath & "||" & rangeStart & "||" & rangeEnd & "||" & wsName

        end tell
        """

        let output: String
        do {
            output = try runAppleScript(script)
        } catch {
            logger.debug("queryXcode: \(error)")
            return nil
        }

        if output == "NO_WINDOW" || output == "NO_FILE" {
            logger.debug("queryXcode: \(output)")
            return nil
        }

        let parts = output.components(separatedBy: "||")
        guard parts.count == 4,
              let start = Int(parts[1]),
              let end = Int(parts[2]) else {
            logger.warning("queryXcode: unexpected output format: \(output.prefix(100))")
            return nil
        }

        return (parts[0], start, end, parts[3])
    }

}

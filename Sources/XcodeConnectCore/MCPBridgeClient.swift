import Foundation
import Logging

private let logger = Logger(label: "bridge")

public final class MCPBridgeClient: @unchecked Sendable, ToolCallable {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var pendingRequests: [JSONRPCId: CheckedContinuation<JSONValue, Error>] = [:]
    private var nextId = 1
    private let lock = NSLock()
    private var readBuffer = Data()
    private var isRunning = false

    public init() {}

    public func start() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["mcpbridge"]

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        self.process = process
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.handleData(data)
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            logger.warning("mcpbridge process terminated with code \(proc.terminationStatus)")
            let pending = self.lock.withLock { () -> [JSONRPCId: CheckedContinuation<JSONValue, Error>] in
                self.isRunning = false
                let p = self.pendingRequests
                self.pendingRequests.removeAll()
                return p
            }
            logger.debug("bridge: failing \(pending.count) pending requests")
            for (_, cont) in pending {
                cont.resume(throwing: BridgeError.processTerminated)
            }
        }

        logger.info("starting mcpbridge process (xcrun mcpbridge)")
        try process.run()
        lock.withLock { isRunning = true }

        try await Task.sleep(nanoseconds: 500_000_000)
        try await initialize()
        logger.info("mcpbridge initialized")
    }

    public func stop() {
        logger.info("stopping mcpbridge")
        stdinPipe?.fileHandleForWriting.closeFile()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        lock.withLock { isRunning = false }
    }

    public func listTools() async throws -> [MCPToolDefinition] {
        let result = try await sendRequest(method: "tools/list")
        guard let tools = result["tools"]?.arrayValue else { return [] }

        return tools.compactMap { tool -> MCPToolDefinition? in
            guard let obj = tool.objectValue,
                  let name = obj["name"]?.stringValue else { return nil }
            let description = obj["description"]?.stringValue
            let inputSchema = obj["inputSchema"]
            return MCPToolDefinition(name: name, description: description, inputSchema: inputSchema)
        }
    }

    public func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        logger.info("bridge callTool: \(name)")
        logger.debug("bridge callTool args: \(arguments.keys.joined(separator: ", "))")
        let params: JSONValue = .object([
            "name": .string(name),
            "arguments": .object(arguments)
        ])
        let result = try await sendRequest(method: "tools/call", params: params)

        guard let contentArray = result["content"]?.arrayValue else {
            logger.warning("bridge callTool \(name): no content array in response")
            return .text("No content in response")
        }

        let content: [MCPContent] = contentArray.compactMap { item in
            guard let obj = item.objectValue,
                  let type = obj["type"]?.stringValue else { return nil }
            let text = obj["text"]?.stringValue
            let data = obj["data"]?.stringValue
            let mimeType = obj["mimeType"]?.stringValue
            return MCPContent(type: type, text: text, data: data, mimeType: mimeType)
        }

        let isError: Bool? = {
            if case .bool(let b) = result["isError"] { return b }
            return nil
        }()

        return MCPToolResult(content: content, isError: isError)
    }

    private func initialize() async throws {
        let initParams: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string("cc-xcode-connect"),
                "version": .string("0.0.1")
            ])
        ])
        _ = try await sendRequest(method: "initialize", params: initParams)
        sendNotification(method: "notifications/initialized")
    }

    private func sendRequest(method: String, params: JSONValue? = nil) async throws -> JSONValue {
        guard lock.withLock({ isRunning }) else {
            logger.error("bridge sendRequest \(method): not running")
            throw BridgeError.notRunning
        }

        let id: JSONRPCId = lock.withLock {
            let current = nextId
            nextId += 1
            return .int(current)
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { pendingRequests[id] = continuation }

            let request = JSONRPCRequest(method: method, params: params, id: id)
            guard let data = try? JSONEncoder().encode(request) else {
                _ = lock.withLock { pendingRequests.removeValue(forKey: id) }
                logger.error("bridge: failed to encode request \(method) id=\(id)")
                continuation.resume(throwing: BridgeError.encodingFailed)
                return
            }

            logger.debug("bridge -> \(method) id=\(id)")
            var message = data
            message.append(contentsOf: [0x0a])
            stdinPipe?.fileHandleForWriting.write(message)
        }
    }

    private func sendNotification(method: String, params: JSONValue? = nil) {
        let notification = JSONRPCNotification(method: method, params: params)
        guard let data = try? JSONEncoder().encode(notification) else { return }
        var message = data
        message.append(contentsOf: [0x0a])
        stdinPipe?.fileHandleForWriting.write(message)
    }

    private func handleData(_ data: Data) {
        readBuffer.append(data)

        var searchStart = readBuffer.startIndex
        while let newlineIndex = readBuffer[searchStart...].firstIndex(of: 0x0a) {
            let lineData = readBuffer[searchStart..<newlineIndex]
            searchStart = readBuffer.index(after: newlineIndex)
            if !lineData.isEmpty {
                handleLine(Data(lineData))
            }
        }

        if searchStart > readBuffer.startIndex {
            readBuffer = Data(readBuffer[searchStart...])
        }
    }

    private func handleLine(_ data: Data) {
        guard let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            logger.warning("bridge: unrecognized message from mcpbridge: \(raw)")
            return
        }
        guard let id = response.id else {
            logger.debug("bridge: received response without id (notification?)")
            return
        }

        let continuation = lock.withLock { pendingRequests.removeValue(forKey: id) }

        if let error = response.error {
            logger.error("bridge <- error id=\(id): [\(error.code)] \(error.message)")
            continuation?.resume(throwing: BridgeError.rpcError(error.code, error.message))
        } else {
            logger.debug("bridge <- ok id=\(id)")
            continuation?.resume(returning: response.result ?? .null)
        }

        if continuation == nil {
            logger.warning("bridge: received response for unknown id=\(id) (no pending request)")
        }
    }
}

public enum BridgeError: Error, LocalizedError {
    case notRunning
    case processTerminated
    case encodingFailed
    case rpcError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: return "Bridge process not running"
        case .processTerminated: return "Bridge process terminated"
        case .encodingFailed: return "Failed to encode request"
        case .rpcError(let code, let msg): return "RPC error \(code): \(msg)"
        }
    }
}

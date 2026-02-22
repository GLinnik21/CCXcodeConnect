import Foundation
import Logging

public struct AdapterServerState {
    public var xcodeRunning: Bool
    public var claudeConnected: Bool
    public var connectedPID: Int32?
    public var workspaceName: String?

    public init(xcodeRunning: Bool = false, claudeConnected: Bool = false, connectedPID: Int32? = nil, workspaceName: String? = nil) {
        self.xcodeRunning = xcodeRunning
        self.claudeConnected = claudeConnected
        self.connectedPID = connectedPID
        self.workspaceName = workspaceName
    }
}

private let logger = Logger(label: "adapter")

public final class AdapterServer: @unchecked Sendable {
    public var onStateChange: ((AdapterServerState) -> Void)?

    private var state = AdapterServerState()
    private var serverPort: Int?
    private var lockFileManager: LockFileManager?
    private var webSocketServer: WebSocketServer?
    private var bridgeClient: MCPBridgeClient?
    private var toolRouter: MCPToolRouter?
    private var editorContext: EditorContext?
    private var xcodeMonitor: XcodeMonitor?
    private var workspacePoller: DispatchSourceTimer?
    private var lastWorkspacePaths: [String] = []

    public init() {}

    @discardableResult
    public func start() async throws -> Int {
        xcodeMonitor = XcodeMonitor { [weak self] running in
            self?.handleXcodeStateChange(running: running)
        }
        xcodeMonitor?.startMonitoring()

        let authToken = UUID().uuidString
        let server = WebSocketServer(authToken: authToken)
        server.onClientConnected = { [weak self] in
            guard let self else { return }
            self.state.claudeConnected = true
            self.onStateChange?(self.state)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let pid = self.lookupClientPID()
                self.state.connectedPID = pid
                self.onStateChange?(self.state)
            }
        }
        server.onClientDisconnected = { [weak self] in
            guard let self else { return }
            self.state.claudeConnected = false
            self.state.connectedPID = nil
            self.onStateChange?(self.state)
        }

        let port = try await server.start()
        self.serverPort = port
        self.webSocketServer = server

        let lockFile = LockFileManager(port: port, authToken: authToken)
        lockFile.write(workspaceFolders: [])
        self.lockFileManager = lockFile

        if XcodeMonitor.isXcodeRunning() {
            handleXcodeStateChange(running: true)
        }

        return port
    }

    public func shutdown() {
        stopWorkspacePolling()
        xcodeMonitor?.stopMonitoring()
        editorContext?.stop()
        bridgeClient?.stop()
        lockFileManager?.remove()
        webSocketServer?.stop()
    }

    private func handleXcodeStateChange(running: Bool) {
        logger.info("Xcode \(running ? "launched" : "quit")")
        state.xcodeRunning = running
        onStateChange?(state)

        if running {
            startBridge()
        } else {
            stopBridge()
        }
    }

    private func startBridge() {
        guard bridgeClient == nil else { return }
        logger.info("starting mcpbridge")

        let client = MCPBridgeClient()
        self.bridgeClient = client

        let router = MCPToolRouter(bridgeClient: client)
        self.toolRouter = router
        webSocketServer?.toolRouter = router

        let context = EditorContext { [weak self] notification in
            self?.webSocketServer?.sendNotification(notification)
        }
        self.editorContext = context
        router.editorContext = context

        let workspaces = WorkspaceDetector.detect()
        lastWorkspacePaths = workspaces.map(\.path)
        if let first = workspaces.first {
            state.workspaceName = first.name
        }
        lockFileManager?.write(workspaceFolders: lastWorkspacePaths)
        onStateChange?(state)
        context.start()
        startWorkspacePolling()

        Task {
            do {
                try await client.start()
                let tabId = try await Self.detectTabIdentifier(bridgeClient: client)
                router.tabIdentifier = tabId
                logger.info("mcpbridge ready, tabIdentifier=\(tabId ?? "nil")")
            } catch {
                logger.error("failed to start bridge: \(error)")
            }
        }
    }

    private func stopBridge() {
        logger.info("stopping mcpbridge")
        stopWorkspacePolling()
        editorContext?.stop()
        editorContext = nil
        bridgeClient?.stop()
        bridgeClient = nil
        toolRouter = nil
        webSocketServer?.toolRouter = nil
        state.workspaceName = nil
        lastWorkspacePaths = []
        lockFileManager?.write(workspaceFolders: [])
        onStateChange?(state)
    }

    private func startWorkspacePolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(3), repeating: .seconds(3))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let workspaces = WorkspaceDetector.detect()
            let paths = workspaces.map(\.path)
            guard paths != self.lastWorkspacePaths else { return }
            self.lastWorkspacePaths = paths
            self.state.workspaceName = workspaces.first?.name
            self.lockFileManager?.write(workspaceFolders: paths)
            self.onStateChange?(self.state)
            if let client = self.bridgeClient {
                Task {
                    let tabId = try? await Self.detectTabIdentifier(bridgeClient: client)
                    self.toolRouter?.tabIdentifier = tabId
                }
            }
        }
        timer.resume()
        self.workspacePoller = timer
    }

    private func stopWorkspacePolling() {
        workspacePoller?.cancel()
        workspacePoller = nil
    }

    private func lookupClientPID() -> Int32? {
        guard let port = serverPort else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "tcp:\(port)", "-sTCP:ESTABLISHED", "-Fp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let myPid = ProcessInfo.processInfo.processIdentifier
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()), pid != myPid {
                return pid
            }
        }
        return nil
    }

    private static func detectTabIdentifier(bridgeClient: MCPBridgeClient) async throws -> String? {
        let result = try await bridgeClient.callTool(name: "XcodeListWindows", arguments: [:])
        guard let textContent = result.content.first(where: { $0.type == "text" }),
              let text = textContent.text else { return nil }

        let message: String
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            message = msg
        } else {
            message = text
        }

        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") else { continue }
            let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            for part in content.components(separatedBy: ", ") {
                let kv = part.components(separatedBy: ": ")
                if kv.count >= 2 && kv[0].trimmingCharacters(in: .whitespaces) == "tabIdentifier" {
                    return kv[1...].joined(separator: ": ").trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
}

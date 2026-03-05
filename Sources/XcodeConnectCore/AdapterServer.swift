import Foundation
import Logging

public struct AdapterServerState {
    public var xcodeRunning: Bool
    public var claudeConnected: Bool
    public var connectedPID: Int32?
    public var workspaceName: String?
    public var workspacePath: String?
    public var port: Int?

    public init(xcodeRunning: Bool = false, claudeConnected: Bool = false, connectedPID: Int32? = nil, workspaceName: String? = nil, workspacePath: String? = nil, port: Int? = nil) {
        self.xcodeRunning = xcodeRunning
        self.claudeConnected = claudeConnected
        self.connectedPID = connectedPID
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.port = port
    }
}

private let logger = Logger(label: "adapter")

public final class AdapterServer: @unchecked Sendable {
    public var onStateChange: ((AdapterServerState) -> Void)?

    private var state = AdapterServerState()
    private var serverPort: Int?
    private var lockFileManager: LockFileManager?
    private var webSocketServer: WebSocketServer?
    private var ownedBridgeClient: MCPBridgeClient?
    private var sharedBridgeClient: (any ToolCallable)?
    private var toolRouter: MCPToolRouter?
    private var editorContext: EditorContext?
    private var xcodeMonitor: XcodeMonitor?
    private var workspacePoller: DispatchSourceTimer?
    private var diagnosticsPoller: DispatchSourceTimer?
    private var lastDiagnosticsSnapshot: [String: String] = [:]
    private var lastWorkspacePaths: [String] = []
    private let targetWorkspace: String?
    private let windowName: String?

    public init(targetWorkspace: String? = nil, windowName: String? = nil, sharedBridgeClient: (any ToolCallable)? = nil) {
        self.targetWorkspace = targetWorkspace
        self.windowName = windowName
        self.sharedBridgeClient = sharedBridgeClient
    }

    @discardableResult
    public func start() async throws -> Int {
        if targetWorkspace == nil {
            xcodeMonitor = XcodeMonitor { [weak self] running in
                self?.handleXcodeStateChange(running: running)
            }
            xcodeMonitor?.startMonitoring()
        }

        if let ws = targetWorkspace {
            state.workspacePath = ws
            state.workspaceName = URL(fileURLWithPath: ws).lastPathComponent
        }

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
        self.state.port = port
        self.webSocketServer = server

        let lockFile = LockFileManager(port: port, authToken: authToken)
        if let ws = targetWorkspace {
            lockFile.write(workspaceFolders: [ws])
        } else {
            lockFile.write(workspaceFolders: [])
        }
        self.lockFileManager = lockFile

        if XcodeMonitor.isXcodeRunning() {
            handleXcodeStateChange(running: true)
        }

        return port
    }

    public func shutdown() {
        stopWorkspacePolling()
        stopDiagnosticsPolling()
        xcodeMonitor?.stopMonitoring()
        editorContext?.stop()
        ownedBridgeClient?.stop()
        lockFileManager?.remove()
        webSocketServer?.stop()
    }

    public func handleXcodeStateChange(running: Bool) {
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
        guard toolRouter == nil else { return }

        let client: any ToolCallable
        if let shared = sharedBridgeClient {
            logger.info("using shared mcpbridge\(targetWorkspace.map { " for \($0)" } ?? "")")
            client = shared
        } else {
            logger.info("starting mcpbridge\(targetWorkspace.map { " for \($0)" } ?? "")")
            let owned = MCPBridgeClient()
            self.ownedBridgeClient = owned
            client = owned
        }

        let router = MCPToolRouter(bridgeClient: client)
        self.toolRouter = router
        webSocketServer?.toolRouter = router

        let wsName = windowName ?? targetWorkspace.map { URL(fileURLWithPath: $0).lastPathComponent }
        let context = EditorContext(workspaceName: wsName) { [weak self] notification in
            self?.webSocketServer?.sendNotification(notification)
        }
        self.editorContext = context
        router.editorContext = context

        if targetWorkspace != nil {
            lockFileManager?.write(workspaceFolders: [targetWorkspace!])
        } else {
            let workspaces = WorkspaceDetector.detect()
            lastWorkspacePaths = workspaces.map(\.path)
            if let first = workspaces.first {
                state.workspaceName = first.name
            }
            logger.info("detected \(workspaces.count) workspace(s): \(workspaces.map(\.name).joined(separator: ", "))")
            lockFileManager?.write(workspaceFolders: lastWorkspacePaths)
        }
        onStateChange?(state)
        context.start()
        startDiagnosticsPolling()

        if targetWorkspace == nil {
            startWorkspacePolling()
        }

        let workspace = targetWorkspace
        if let owned = ownedBridgeClient {
            Task {
                do {
                    try await owned.start()
                    let tabId = try await Self.detectTabIdentifier(bridgeClient: owned, forWorkspace: workspace)
                    router.tabIdentifier = tabId
                    logger.info("mcpbridge ready, tabIdentifier=\(tabId ?? "nil")")
                } catch {
                    logger.error("failed to start bridge: \(error)")
                }
            }
        } else {
            Task {
                do {
                    let tabId = try await Self.detectTabIdentifier(bridgeClient: client, forWorkspace: workspace)
                    router.tabIdentifier = tabId
                    logger.info("tabIdentifier=\(tabId ?? "nil") for \(workspace ?? "default")")
                } catch {
                    logger.error("failed to detect tab: \(error)")
                }
            }
        }
    }

    private func stopBridge() {
        logger.info("stopping mcpbridge")
        stopWorkspacePolling()
        stopDiagnosticsPolling()
        editorContext?.stop()
        editorContext = nil
        ownedBridgeClient?.stop()
        ownedBridgeClient = nil
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
            logger.info("workspace change detected: \(workspaces.map(\.name).joined(separator: ", "))")
            self.lastWorkspacePaths = paths
            self.state.workspaceName = workspaces.first?.name
            self.lockFileManager?.write(workspaceFolders: paths)
            self.onStateChange?(self.state)
            let client: (any ToolCallable)? = self.ownedBridgeClient ?? self.sharedBridgeClient
            if let client {
                Task {
                    let tabId = try? await Self.detectTabIdentifier(bridgeClient: client, forWorkspace: nil)
                    logger.info("workspace poll: updated tabIdentifier=\(tabId ?? "nil")")
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

    private func startDiagnosticsPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(3), repeating: .seconds(3))
        timer.setEventHandler { [weak self] in
            guard let self, self.state.claudeConnected else { return }
            Task { await self.pollDiagnostics() }
        }
        timer.resume()
        self.diagnosticsPoller = timer
    }

    private func stopDiagnosticsPolling() {
        diagnosticsPoller?.cancel()
        diagnosticsPoller = nil
        lastDiagnosticsSnapshot = [:]
    }

    private func pollDiagnostics() async {
        guard let client = ownedBridgeClient ?? sharedBridgeClient,
              let tabId = toolRouter?.tabIdentifier else { return }

        let args: [String: JSONValue] = [
            "tabIdentifier": .string(tabId),
            "severity": .string("remark")
        ]

        guard let result = try? await client.callTool(name: "XcodeListNavigatorIssues", arguments: args),
              let text = result.content.first?.text,
              let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode(JSONValue.self, from: data),
              let issues = raw["issues"]?.arrayValue else { return }

        var snapshot: [String: String] = [:]
        for issue in issues {
            guard let path = issue["path"]?.stringValue else { continue }
            let uri = "file://\(path)"
            let entry = "\(issue["line"]?.intValue ?? 0):\(issue["severity"]?.stringValue ?? ""):\(issue["message"]?.stringValue ?? "")"
            snapshot[uri, default: ""] += entry + "|"
        }

        let changedUris = snapshot.keys.filter { snapshot[$0] != lastDiagnosticsSnapshot[$0] }
            + lastDiagnosticsSnapshot.keys.filter { snapshot[$0] == nil }

        guard !changedUris.isEmpty else { return }
        lastDiagnosticsSnapshot = snapshot

        let params: JSONValue = .object(["uris": .array(changedUris.map { .string($0) })])
        let notification = JSONRPCNotification(method: "diagnostics_changed", params: params)
        logger.info("diagnostics_changed: \(changedUris.count) file(s) changed")
        webSocketServer?.sendNotification(notification)
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

    struct WindowInfo {
        let tabIdentifier: String
        let workspacePath: String
        let isFront: Bool
    }

    static func parseWindowList(from text: String) -> [WindowInfo] {
        let message: String
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String {
            message = msg
        } else {
            message = text
        }

        var windows: [WindowInfo] = []
        for line in message.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let isFront = trimmed.hasPrefix("*")
            let content: String
            if isFront {
                content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else {
                content = trimmed
            }

            var tabId: String?
            var wsPath: String?
            for part in content.components(separatedBy: ", ") {
                let kv = part.components(separatedBy: ": ")
                guard kv.count >= 2 else { continue }
                let key = kv[0].trimmingCharacters(in: .whitespaces)
                let value = kv[1...].joined(separator: ": ").trimmingCharacters(in: .whitespaces)
                if key == "tabIdentifier" { tabId = value }
                if key == "workspacePath" { wsPath = value }
            }

            if let tabId, let wsPath {
                windows.append(WindowInfo(tabIdentifier: tabId, workspacePath: wsPath, isFront: isFront))
            }
        }
        return windows
    }

    static func detectTabIdentifier(bridgeClient: any ToolCallable, forWorkspace workspace: String? = nil) async throws -> String? {
        let result = try await bridgeClient.callTool(name: "XcodeListWindows", arguments: [:])
        guard let textContent = result.content.first(where: { $0.type == "text" }),
              let text = textContent.text else { return nil }

        let windows = parseWindowList(from: text)

        if let workspace {
            for w in windows {
                let wsDir = URL(fileURLWithPath: w.workspacePath).deletingLastPathComponent().path
                if wsDir == workspace || w.workspacePath.hasPrefix(workspace) {
                    return w.tabIdentifier
                }
            }
            return nil
        }

        return windows.first(where: { $0.isFront })?.tabIdentifier ?? windows.first?.tabIdentifier
    }
}

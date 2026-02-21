import SwiftUI

@main
struct XcodeIDEAdapterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.coordinator)
        } label: {
            Label("Xcode IDE Adapter", systemImage: appDelegate.coordinator.statusIcon)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await coordinator.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var xcodeRunning = false
    @Published var claudeConnected = false
    @Published var workspaceName: String?
    @Published var statusIcon = "xmark.circle"

    private var lockFileManager: LockFileManager?
    private var webSocketServer: WebSocketServer?
    private var bridgeClient: MCPBridgeClient?
    private var toolRouter: MCPToolRouter?
    private var editorContext: EditorContext?
    private var xcodeMonitor: XcodeMonitor?

    func start() async {
        xcodeMonitor = XcodeMonitor { [weak self] running in
            Task { @MainActor in
                self?.handleXcodeStateChange(running: running)
            }
        }
        xcodeMonitor?.startMonitoring()

        let authToken = UUID().uuidString
        let server = WebSocketServer(authToken: authToken)
        server.onClientConnected = { [weak self] in
            Task { @MainActor in
                self?.claudeConnected = true
                self?.updateStatusIcon()
            }
        }
        server.onClientDisconnected = { [weak self] in
            Task { @MainActor in
                self?.claudeConnected = false
                self?.updateStatusIcon()
            }
        }

        do {
            let port = try await server.start()
            self.webSocketServer = server

            let lockFile = LockFileManager(port: port, authToken: authToken)
            lockFile.write(workspaceFolders: [])
            self.lockFileManager = lockFile

            if XcodeMonitor.isXcodeRunning() {
                handleXcodeStateChange(running: true)
            }
        } catch {
            print("Failed to start WebSocket server: \(error)")
        }
    }

    func shutdown() {
        editorContext?.stop()
        bridgeClient?.stop()
        lockFileManager?.remove()
        webSocketServer?.stop()
    }

    private func handleXcodeStateChange(running: Bool) {
        xcodeRunning = running
        updateStatusIcon()

        if running {
            startBridge()
        } else {
            stopBridge()
        }
    }

    private func startBridge() {
        guard bridgeClient == nil else { return }

        let client = MCPBridgeClient()
        self.bridgeClient = client

        let router = MCPToolRouter(bridgeClient: client)
        self.toolRouter = router
        webSocketServer?.toolRouter = router

        let context = EditorContext { [weak self] notification in
            self?.webSocketServer?.sendNotification(notification)
        }
        self.editorContext = context

        let workspaces = WorkspaceDetector.detect()
        if let first = workspaces.first {
            self.workspaceName = first.name
        }
        lockFileManager?.write(workspaceFolders: workspaces.map(\.path))
        context.start()

        Task {
            do {
                try await client.start()
                let tabId = try await Self.detectTabIdentifier(bridgeClient: client)
                router.tabIdentifier = tabId
            } catch {
                print("Failed to start bridge: \(error)")
            }
        }
    }

    private func stopBridge() {
        editorContext?.stop()
        editorContext = nil
        bridgeClient?.stop()
        bridgeClient = nil
        toolRouter = nil
        webSocketServer?.toolRouter = nil
        workspaceName = nil
        lockFileManager?.write(workspaceFolders: [])
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

    private func updateStatusIcon() {
        if claudeConnected && xcodeRunning {
            statusIcon = "checkmark.circle.fill"
        } else if xcodeRunning {
            statusIcon = "circle"
        } else {
            statusIcon = "xmark.circle"
        }
    }
}

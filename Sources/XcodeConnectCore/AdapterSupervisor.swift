import Foundation
import Logging

private let logger = Logger(label: "supervisor")

public final class AdapterSupervisor: @unchecked Sendable {
    public var onStateChange: (([AdapterServerState]) -> Void)?

    private let queue = DispatchQueue(label: "supervisor.sync")
    private var workers: [String: AdapterServer] = [:]
    private var workerStates: [String: AdapterServerState] = [:]
    private var xcodeMonitor: XcodeMonitor?
    private var workspacePoller: DispatchSourceTimer?
    private var bridgeClient: MCPBridgeClient?
    private var xcodeRunning = false

    private let settings: AdapterSettingsProviding

    public init(settings: AdapterSettingsProviding) {
        self.settings = settings
    }

    public func start() {
        xcodeMonitor = XcodeMonitor { [weak self] running in
            self?.handleXcodeStateChange(running: running)
        }
        xcodeMonitor?.startMonitoring()

        if XcodeMonitor.isXcodeRunning() {
            handleXcodeStateChange(running: true)
        }
    }

    public func restartPolling() {
        stopPolling()
        startPolling()
        queue.sync {
            for (_, server) in workers {
                server.restartPolling()
            }
        }
    }

    public func shutdown() {
        stopPolling()
        xcodeMonitor?.stopMonitoring()
        tearDownAllWorkers()
    }

    private func tearDownAllWorkers() {
        queue.sync {
            for (_, server) in workers {
                server.shutdown()
            }
            workers.removeAll()
            workerStates.removeAll()
        }
        bridgeClient?.stop()
        bridgeClient = nil
    }

    private func handleXcodeStateChange(running: Bool) {
        logger.info("Xcode \(running ? "launched" : "quit")")
        queue.sync { xcodeRunning = running }

        if running {
            startBridge()
        } else {
            stopPolling()
            tearDownAllWorkers()
            onStateChange?([])
        }
    }

    private func startBridge() {
        guard bridgeClient == nil else {
            pollWorkspaces()
            startPolling()
            return
        }

        Task {
            await BridgeRetry.execute(
                settings: self.settings,
                shouldContinue: { [weak self] in
                    self?.queue.sync { self?.xcodeRunning ?? false } ?? false
                },
                operation: { [weak self] in
                    guard let self else { return }
                    let client = MCPBridgeClient()
                    self.queue.sync { self.bridgeClient = client }
                    do {
                        try await client.start()
                        logger.info("shared mcpbridge ready")
                        self.pollWorkspaces()
                        self.startPolling()
                    } catch {
                        client.stop()
                        self.queue.sync { self.bridgeClient = nil }
                        throw error
                    }
                }
            )
        }
    }

    private func startPolling() {
        guard workspacePoller == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        let ms = Int(settings.workspacePollingInterval * 1000)
        timer.schedule(deadline: .now() + .milliseconds(ms), repeating: .milliseconds(ms))
        timer.setEventHandler { [weak self] in
            self?.pollWorkspaces()
        }
        timer.resume()
        self.workspacePoller = timer
    }

    private func stopPolling() {
        workspacePoller?.cancel()
        workspacePoller = nil
    }

    private func pollWorkspaces() {
        let workspaces = WorkspaceDetector.detect()
        let currentPaths = Set(workspaces.map(\.path))

        queue.sync {
            let existingPaths = Set(workers.keys)

            let added = currentPaths.subtracting(existingPaths)
            let removed = existingPaths.subtracting(currentPaths)

            for path in removed {
                destroyWorkerLocked(path: path)
            }

            for workspace in workspaces where added.contains(workspace.path) {
                createWorkerLocked(workspace: workspace)
            }

            if !added.isEmpty || !removed.isEmpty {
                logger.info("workspaces: \(workers.count) active (\(added.count) added, \(removed.count) removed)")
                let states = collectStatesLocked()
                onStateChange?(states)
            }
        }
    }

    private func createWorkerLocked(workspace: WorkspaceInfo) {
        logger.info("creating worker for \(workspace.name) at \(workspace.path)")
        let server = AdapterServer(settings: settings, targetWorkspace: workspace.path, windowName: workspace.windowName, sharedBridgeClient: bridgeClient)
        let path = workspace.path
        server.onStateChange = { [weak self] state in
            guard let self else { return }
            self.queue.sync {
                self.workerStates[path] = state
                let states = self.collectStatesLocked()
                self.onStateChange?(states)
            }
        }
        workers[path] = server
        workerStates[path] = AdapterServerState(
            xcodeRunning: xcodeRunning,
            workspaceName: workspace.name,
            workspacePath: workspace.path
        )

        Task {
            do {
                let port = try await server.start()
                logger.info("worker started for \(workspace.name) on port \(port)")
            } catch {
                logger.error("failed to start worker for \(workspace.name): \(error)")
                self.queue.sync {
                    self.workers.removeValue(forKey: path)
                    self.workerStates.removeValue(forKey: path)
                    let states = self.collectStatesLocked()
                    self.onStateChange?(states)
                }
            }
        }
    }

    private func destroyWorkerLocked(path: String) {
        guard let server = workers.removeValue(forKey: path) else { return }
        workerStates.removeValue(forKey: path)
        let name = URL(fileURLWithPath: path).lastPathComponent
        logger.info("destroying worker for \(name)")
        server.shutdown()
    }

    private func collectStatesLocked() -> [AdapterServerState] {
        workerStates.sorted(by: { $0.key < $1.key }).map(\.value)
    }
}

import XcodeConnectCore
import ServiceManagement
import SwiftUI

@main
struct CCXcodeConnectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.coordinator)
        } label: {
            Label("CC Xcode Connect", systemImage: appDelegate.coordinator.statusIcon)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? SMAppService.mainApp.register()
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var xcodeRunning = false
    @Published var workspaceStates: [AdapterServerState] = []

    var statusIcon: String {
        let anyConnected = workspaceStates.contains { $0.claudeConnected }
        if anyConnected && xcodeRunning {
            return "checkmark.circle.fill"
        } else if xcodeRunning {
            return "circle"
        } else {
            return "xmark.circle"
        }
    }

    private let supervisor = AdapterSupervisor()

    func start() {
        supervisor.onStateChange = { [weak self] states in
            Task { @MainActor in
                guard let self else { return }
                self.workspaceStates = states
                self.xcodeRunning = states.first?.xcodeRunning ?? false
            }
        }
        supervisor.start()
    }

    func shutdown() {
        supervisor.shutdown()
    }
}

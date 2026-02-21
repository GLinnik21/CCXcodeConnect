import IDEAdapterCore
import ServiceManagement
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
        try? SMAppService.mainApp.register()
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

    var statusIcon: String {
        if claudeConnected && xcodeRunning {
            return "checkmark.circle.fill"
        } else if xcodeRunning {
            return "circle"
        } else {
            return "xmark.circle"
        }
    }

    private let server = AdapterServer()

    func start() async {
        server.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.xcodeRunning = state.xcodeRunning
                self.claudeConnected = state.claudeConnected
                self.workspaceName = state.workspaceName
            }
        }

        do {
            try await server.start()
        } catch {
            print("Failed to start: \(error)")
        }
    }

    func shutdown() {
        server.shutdown()
    }
}

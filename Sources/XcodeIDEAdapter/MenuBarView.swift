import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }

            if let workspace = coordinator.workspaceName {
                Text("Workspace: \(workspace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Quit") {
                coordinator.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }

    private var statusColor: Color {
        if coordinator.claudeConnected && coordinator.xcodeRunning {
            return .green
        } else if coordinator.xcodeRunning {
            return .yellow
        } else {
            return .red
        }
    }

    private var statusText: String {
        if coordinator.claudeConnected && coordinator.xcodeRunning {
            return "Connected"
        } else if coordinator.xcodeRunning {
            return "Xcode running, waiting for Claude"
        } else {
            return "Xcode not running"
        }
    }
}

import SwiftUI
import IDEAdapterCore

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

            if !coordinator.workspaceStates.isEmpty {
                Divider()

                ForEach(Array(coordinator.workspaceStates.enumerated()), id: \.offset) { _, state in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.claudeConnected ? Color.green : Color.yellow)
                            .frame(width: 6, height: 6)
                        Text(state.workspaceName ?? "Unknown")
                            .font(.caption)
                        if let pid = state.connectedPID {
                            Text("(PID \(pid))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
        let anyConnected = coordinator.workspaceStates.contains { $0.claudeConnected }
        if anyConnected && coordinator.xcodeRunning {
            return .green
        } else if coordinator.xcodeRunning {
            return .yellow
        } else {
            return .red
        }
    }

    private var statusText: String {
        let connectedCount = coordinator.workspaceStates.filter { $0.claudeConnected }.count
        let totalCount = coordinator.workspaceStates.count

        if !coordinator.xcodeRunning {
            return "Xcode not running"
        } else if totalCount == 0 {
            return "No workspaces detected"
        } else if connectedCount > 0 {
            return "\(totalCount) workspace\(totalCount == 1 ? "" : "s"), \(connectedCount) connected"
        } else {
            return "\(totalCount) workspace\(totalCount == 1 ? "" : "s"), waiting for Claude"
        }
    }
}

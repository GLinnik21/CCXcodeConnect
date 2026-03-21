import AppKit
import ServiceManagement
import XcodeConnectCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    let settings = AdapterSettings()
    private var supervisor: AdapterSupervisor?
    private var statusItem: NSStatusItem!
    private var xcodeRunning = false
    private var workspaceStates: [AdapterServerState] = []
    private var cachedDots: [NSColor: NSImage] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        rebuildMenu()

        let supervisor = AdapterSupervisor(settings: settings)
        self.supervisor = supervisor
        supervisor.onStateChange = { [weak self] states in
            DispatchQueue.main.async {
                guard let self else { return }
                self.workspaceStates = states
                self.xcodeRunning = states.first?.xcodeRunning ?? false
                self.updateStatusIcon()
                self.rebuildMenu()
            }
        }
        supervisor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        supervisor?.shutdown()
    }

    private var anyConnected: Bool {
        workspaceStates.contains { $0.claudeConnected }
    }

    private func updateStatusIcon() {
        let imageName: String
        if anyConnected && xcodeRunning {
            imageName = "checkmark.circle.fill"
        } else if xcodeRunning {
            imageName = "circle"
        } else {
            imageName = "xmark.circle"
        }
        statusItem.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "CC Xcode Connect")
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.image = statusDot(color: statusColor)
        menu.addItem(statusItem)

        if !workspaceStates.isEmpty {
            menu.addItem(.separator())
            for state in workspaceStates {
                let color: NSColor = state.claudeConnected ? .systemGreen : .systemYellow
                var title = state.workspaceName ?? "Unknown"
                if let pid = state.connectedPID {
                    title += " (PID \(pid))"
                }
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.image = statusDot(color: color)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        self.statusItem.menu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.show(settings: settings)
    }

    @objc private func quit() {
        supervisor?.shutdown()
        NSApp.terminate(nil)
    }

    private var statusColor: NSColor {
        if anyConnected && xcodeRunning {
            return .systemGreen
        } else if xcodeRunning {
            return .systemYellow
        } else {
            return .systemRed
        }
    }

    private var statusText: String {
        let connectedCount = workspaceStates.filter { $0.claudeConnected }.count
        let totalCount = workspaceStates.count

        if !xcodeRunning {
            return "Xcode not running"
        } else if totalCount == 0 {
            return "No workspaces detected"
        } else if connectedCount > 0 {
            return "\(totalCount) workspace\(totalCount == 1 ? "" : "s"), \(connectedCount) connected"
        } else {
            return "\(totalCount) workspace\(totalCount == 1 ? "" : "s"), waiting for Claude"
        }
    }

    private func statusDot(color: NSColor) -> NSImage {
        if let cached = cachedDots[color] { return cached }
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        cachedDots[color] = image
        return image
    }
}

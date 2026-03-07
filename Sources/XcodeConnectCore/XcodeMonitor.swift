import AppKit

public final class XcodeMonitor {
    private let onStateChange: (Bool) -> Void
    private var observer: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    public init(onStateChange: @escaping (Bool) -> Void) {
        self.onStateChange = onStateChange
    }

    public func startMonitoring() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier?.hasPrefix("com.apple.dt.Xcode") == true else { return }
            self?.onStateChange(true)
        }

        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier?.hasPrefix("com.apple.dt.Xcode") == true else { return }
            self?.onStateChange(false)
        }
    }

    public func stopMonitoring() {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    public static func isXcodeRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier?.hasPrefix("com.apple.dt.Xcode") == true }
    }
}

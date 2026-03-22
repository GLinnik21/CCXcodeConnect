import Foundation

public protocol AdapterSettingsProviding: Sendable {
    var diagnosticsPollingEnabled: Bool { get }
    var diagnosticsPollingInterval: TimeInterval { get }
    var workspacePollingInterval: TimeInterval { get }
    var editorPollingInterval: TimeInterval { get }
    var bridgeMaxRetries: Int { get }
    var bridgeMaxRetryDelay: Int { get }
}

public final class AdapterSettings: AdapterSettingsProviding, @unchecked Sendable {
    private enum Key: String, CaseIterable {
        case launchAtLogin = "cc_launchAtLogin"
        case diagnosticsPollingEnabled = "cc_diagnosticsPollingEnabled"
        case diagnosticsPollingInterval = "cc_diagnosticsPollingInterval"
        case workspacePollingInterval = "cc_workspacePollingInterval"
        case editorPollingInterval = "cc_editorPollingInterval"
        case bridgeMaxRetries = "cc_bridgeMaxRetries"
        case bridgeMaxRetryDelay = "cc_bridgeMaxRetryDelay"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.launchAtLogin.rawValue: true,
            Key.diagnosticsPollingEnabled.rawValue: false,
            Key.diagnosticsPollingInterval.rawValue: 3.0,
            Key.workspacePollingInterval.rawValue: 3.0,
            Key.editorPollingInterval.rawValue: 0.5,
            Key.bridgeMaxRetries.rawValue: 10,
            Key.bridgeMaxRetryDelay.rawValue: 10,
        ])
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue) }
    }

    public var diagnosticsPollingEnabled: Bool {
        get { defaults.bool(forKey: Key.diagnosticsPollingEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.diagnosticsPollingEnabled.rawValue) }
    }

    public var diagnosticsPollingInterval: TimeInterval {
        get { defaults.double(forKey: Key.diagnosticsPollingInterval.rawValue) }
        set { defaults.set(newValue, forKey: Key.diagnosticsPollingInterval.rawValue) }
    }

    public var workspacePollingInterval: TimeInterval {
        get { defaults.double(forKey: Key.workspacePollingInterval.rawValue) }
        set { defaults.set(newValue, forKey: Key.workspacePollingInterval.rawValue) }
    }

    public var editorPollingInterval: TimeInterval {
        get { defaults.double(forKey: Key.editorPollingInterval.rawValue) }
        set { defaults.set(newValue, forKey: Key.editorPollingInterval.rawValue) }
    }

    public var bridgeMaxRetries: Int {
        get { defaults.integer(forKey: Key.bridgeMaxRetries.rawValue) }
        set { defaults.set(newValue, forKey: Key.bridgeMaxRetries.rawValue) }
    }

    public var bridgeMaxRetryDelay: Int {
        get { defaults.integer(forKey: Key.bridgeMaxRetryDelay.rawValue) }
        set { defaults.set(newValue, forKey: Key.bridgeMaxRetryDelay.rawValue) }
    }

    public func resetToDefaults() {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}

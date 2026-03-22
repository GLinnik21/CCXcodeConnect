import XCTest
@testable import XcodeConnectCore

final class AdapterSettingsTests: XCTestCase {

    private func makeSettings() -> (AdapterSettings, UserDefaults) {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AdapterSettings(defaults: defaults)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (settings, defaults)
    }

    func testDefaultValues() {
        let (settings, _) = makeSettings()
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertFalse(settings.diagnosticsPollingEnabled)
        XCTAssertEqual(settings.diagnosticsPollingInterval, 3.0)
        XCTAssertEqual(settings.workspacePollingInterval, 3.0)
        XCTAssertEqual(settings.editorPollingInterval, 0.5)
        XCTAssertEqual(settings.bridgeMaxRetries, 10)
        XCTAssertEqual(settings.bridgeMaxRetryDelay, 10)
    }

    func testPersistence() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let settings1 = AdapterSettings(defaults: defaults)
        settings1.diagnosticsPollingInterval = 7.0
        settings1.bridgeMaxRetries = 42

        let settings2 = AdapterSettings(defaults: defaults)
        XCTAssertEqual(settings2.diagnosticsPollingInterval, 7.0)
        XCTAssertEqual(settings2.bridgeMaxRetries, 42)
    }

    func testResetToDefaults() {
        let (settings, _) = makeSettings()
        settings.diagnosticsPollingInterval = 99
        settings.workspacePollingInterval = 99
        settings.editorPollingInterval = 99
        settings.bridgeMaxRetries = 99
        settings.bridgeMaxRetryDelay = 99
        settings.diagnosticsPollingEnabled = false
        settings.launchAtLogin = false

        settings.resetToDefaults()

        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertFalse(settings.diagnosticsPollingEnabled)
        XCTAssertEqual(settings.diagnosticsPollingInterval, 3.0)
        XCTAssertEqual(settings.workspacePollingInterval, 3.0)
        XCTAssertEqual(settings.editorPollingInterval, 0.5)
        XCTAssertEqual(settings.bridgeMaxRetries, 10)
        XCTAssertEqual(settings.bridgeMaxRetryDelay, 10)
    }

    func testEditorContextRestartsWithoutCrash() {
        let mock = MockSettings()
        mock.editorPollingInterval = 0.05

        let context = EditorContext(settings: mock, workspaceName: "TestWorkspace") { _ in }
        context.start()

        mock.editorPollingInterval = 0.02
        context.restart()
        context.restart()

        context.stop()
    }

    func testEditorContextStopStartCycle() {
        let mock = MockSettings()
        let context = EditorContext(settings: mock, workspaceName: "Test") { _ in }

        context.start()
        context.stop()
        context.start()
        context.stop()
    }
}

private final class MockSettings: AdapterSettingsProviding, @unchecked Sendable {
    var diagnosticsPollingEnabled: Bool = true
    var diagnosticsPollingInterval: TimeInterval = 3.0
    var workspacePollingInterval: TimeInterval = 3.0
    var editorPollingInterval: TimeInterval = 0.5
    var bridgeMaxRetries: Int = 10
    var bridgeMaxRetryDelay: Int = 10
}

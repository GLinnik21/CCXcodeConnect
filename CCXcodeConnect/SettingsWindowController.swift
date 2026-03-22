import AppKit
import ServiceManagement
import XcodeConnectCore

final class SettingsWindowController: NSWindowController {
    private static var instance: SettingsWindowController?

    static func show(settings: AdapterSettings) {
        if instance == nil {
            instance = SettingsWindowController(settings: settings)
        }
        instance?.window?.level = .floating
        instance?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    init(settings: AdapterSettings) {
        let viewController = SettingsViewController(settings: settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.title = "CCXcodeConnect Settings"
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class SettingsViewController: NSViewController {
    private let settings: AdapterSettings
    private let labelWidth: CGFloat = 140

    private let launchAtLoginSwitch = NSSwitch()
    private let diagnosticsEnabledSwitch = NSSwitch()
    private let diagnosticsIntervalField = NSTextField()
    private let diagnosticsIntervalStepper = NSStepper()
    private let workspaceIntervalField = NSTextField()
    private let workspaceIntervalStepper = NSStepper()
    private let editorIntervalField = NSTextField()
    private let editorIntervalStepper = NSStepper()
    private let maxRetriesField = NSTextField()
    private let maxRetriesStepper = NSStepper()
    private let maxRetryDelayField = NSTextField()
    private let maxRetryDelayStepper = NSStepper()

    init(settings: AdapterSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        configureStepper(diagnosticsIntervalStepper, min: 1, max: 60, increment: 1)
        configureStepper(workspaceIntervalStepper, min: 1, max: 60, increment: 1)
        configureStepper(editorIntervalStepper, min: 0.1, max: 5, increment: 0.1)
        configureStepper(maxRetriesStepper, min: 1, max: 100, increment: 1)
        configureStepper(maxRetryDelayStepper, min: 1, max: 120, increment: 1)

        configureField(diagnosticsIntervalField, action: #selector(diagnosticsIntervalChanged))
        configureField(workspaceIntervalField, action: #selector(workspaceIntervalChanged))
        configureField(editorIntervalField, action: #selector(editorIntervalChanged))
        configureField(maxRetriesField, action: #selector(maxRetriesChanged))
        configureField(maxRetryDelayField, action: #selector(maxRetryDelayChanged))

        diagnosticsIntervalStepper.target = self
        diagnosticsIntervalStepper.action = #selector(diagnosticsIntervalChanged)
        workspaceIntervalStepper.target = self
        workspaceIntervalStepper.action = #selector(workspaceIntervalChanged)
        editorIntervalStepper.target = self
        editorIntervalStepper.action = #selector(editorIntervalChanged)
        maxRetriesStepper.target = self
        maxRetriesStepper.action = #selector(maxRetriesChanged)
        maxRetryDelayStepper.target = self
        maxRetryDelayStepper.action = #selector(maxRetryDelayChanged)

        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)
        diagnosticsEnabledSwitch.target = self
        diagnosticsEnabledSwitch.action = #selector(diagnosticsEnabledChanged)

        // MARK: - General

        stack.addArrangedSubview(makeSection("General", description: nil, rows: [
            makeFormRow(label: "Launch at Login", control: launchAtLoginSwitch),
            makeHint("Automatically start CCXcodeConnect when you log in."),
        ]))

        stack.addArrangedSubview(makeSeparator())

        // MARK: - Polling

        let diagnosticsRow = NSStackView(views: [
            diagnosticsEnabledSwitch,
            makeFieldStepper(diagnosticsIntervalField, diagnosticsIntervalStepper, suffix: "sec"),
        ])
        diagnosticsRow.orientation = .horizontal
        diagnosticsRow.alignment = .centerY
        diagnosticsRow.spacing = 10

        stack.addArrangedSubview(makeSection(
            "Polling",
            description: "How often the adapter checks Xcode for changes. Lower values are more responsive but use more CPU.",
            rows: [
                makeFormRow(label: "Workspace", control: makeFieldStepper(workspaceIntervalField, workspaceIntervalStepper, suffix: "sec")),
                makeHint("How often to detect opened or closed projects."),
                makeFormRow(label: "Editor Selection", control: makeFieldStepper(editorIntervalField, editorIntervalStepper, suffix: "sec")),
                makeHint("How often to track cursor and selection in Xcode."),
                makeFormRow(label: "Diagnostics", control: diagnosticsRow),
                makeHint("Pushes build errors/warnings proactively. Claude already polls diagnostics on its own. Not yet consumed by CLI. Experimental."),
            ]
        ))

        stack.addArrangedSubview(makeSeparator())

        // MARK: - Bridge Retry

        stack.addArrangedSubview(makeSection(
            "Bridge Retry",
            description: "Controls reconnection to Xcode's MCP bridge when it becomes unavailable.",
            rows: [
                makeFormRow(label: "Max Retries", control: makeFieldStepper(maxRetriesField, maxRetriesStepper, suffix: nil)),
                makeHint("How many times to retry before giving up."),
                makeFormRow(label: "Max Delay", control: makeFieldStepper(maxRetryDelayField, maxRetryDelayStepper, suffix: "sec")),
                makeHint("Maximum wait between retry attempts."),
            ]
        ))

        stack.addArrangedSubview(makeSeparator())

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetButton.controlSize = .regular
        stack.addArrangedSubview(resetButton)

        scroll.documentView = stack
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        self.view = container
        loadValues()
    }

    private func loadValues() {
        launchAtLoginSwitch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        diagnosticsEnabledSwitch.state = settings.diagnosticsPollingEnabled ? .on : .off
        updateDiagnosticsFieldsEnabled()
        setFieldValue(diagnosticsIntervalField, diagnosticsIntervalStepper, settings.diagnosticsPollingInterval)
        setFieldValue(workspaceIntervalField, workspaceIntervalStepper, settings.workspacePollingInterval)
        setFieldValue(editorIntervalField, editorIntervalStepper, settings.editorPollingInterval)
        setFieldValue(maxRetriesField, maxRetriesStepper, Double(settings.bridgeMaxRetries))
        setFieldValue(maxRetryDelayField, maxRetryDelayStepper, Double(settings.bridgeMaxRetryDelay))
    }

    private func setFieldValue(_ field: NSTextField, _ stepper: NSStepper, _ value: Double) {
        stepper.doubleValue = value
        field.stringValue = formatValue(value, for: stepper)
    }

    private func formatValue(_ value: Double, for stepper: NSStepper) -> String {
        if stepper.increment == 1 && stepper.minValue >= 1 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }

    // MARK: - Actions

    @objc private func launchAtLoginChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        settings.launchAtLogin = enabled
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    @objc private func diagnosticsEnabledChanged(_ sender: NSSwitch) {
        settings.diagnosticsPollingEnabled = sender.state == .on
        updateDiagnosticsFieldsEnabled()
        notifyPollingChanged()
    }

    private func updateDiagnosticsFieldsEnabled() {
        let enabled = settings.diagnosticsPollingEnabled
        diagnosticsIntervalField.isEnabled = enabled
        diagnosticsIntervalStepper.isEnabled = enabled
    }

    @objc private func diagnosticsIntervalChanged(_ sender: Any) {
        syncStepperField(field: diagnosticsIntervalField, stepper: diagnosticsIntervalStepper, sender: sender)
        settings.diagnosticsPollingInterval = diagnosticsIntervalStepper.doubleValue
        notifyPollingChanged()
    }

    @objc private func workspaceIntervalChanged(_ sender: Any) {
        syncStepperField(field: workspaceIntervalField, stepper: workspaceIntervalStepper, sender: sender)
        settings.workspacePollingInterval = workspaceIntervalStepper.doubleValue
        notifyPollingChanged()
    }

    @objc private func editorIntervalChanged(_ sender: Any) {
        syncStepperField(field: editorIntervalField, stepper: editorIntervalStepper, sender: sender)
        settings.editorPollingInterval = editorIntervalStepper.doubleValue
        notifyPollingChanged()
    }

    private func notifyPollingChanged() {
        (NSApp.delegate as? AppDelegate)?.restartPolling()
    }

    @objc private func maxRetriesChanged(_ sender: Any) {
        syncStepperField(field: maxRetriesField, stepper: maxRetriesStepper, sender: sender)
        settings.bridgeMaxRetries = Int(maxRetriesStepper.doubleValue)
    }

    @objc private func maxRetryDelayChanged(_ sender: Any) {
        syncStepperField(field: maxRetryDelayField, stepper: maxRetryDelayStepper, sender: sender)
        settings.bridgeMaxRetryDelay = Int(maxRetryDelayStepper.doubleValue)
    }

    @objc private func resetToDefaults(_ sender: Any) {
        settings.resetToDefaults()
        loadValues()
        notifyPollingChanged()
    }

    private func syncStepperField(field: NSTextField, stepper: NSStepper, sender: Any) {
        if sender is NSStepper {
            field.stringValue = formatValue(stepper.doubleValue, for: stepper)
        } else {
            let val = max(stepper.minValue, min(stepper.maxValue, field.doubleValue))
            stepper.doubleValue = val
            field.stringValue = formatValue(val, for: stepper)
        }
    }

    // MARK: - Layout Helpers

    private func makeSection(_ title: String, description: String?, rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .labelColor
        stack.addArrangedSubview(header)

        if let description {
            let desc = NSTextField(wrappingLabelWithString: description)
            desc.font = .systemFont(ofSize: 11)
            desc.textColor = .tertiaryLabelColor
            desc.preferredMaxLayoutWidth = 410
            stack.addArrangedSubview(desc)
            stack.setCustomSpacing(12, after: desc)
        }

        for row in rows {
            stack.addArrangedSubview(row)
        }
        return stack
    }

    private func makeFormRow(label text: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: labelWidth)
        ])

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeFieldStepper(_ field: NSTextField, _ stepper: NSStepper, suffix: String?) -> NSView {
        var views: [NSView] = [field, stepper]
        if let suffix {
            let suffixLabel = NSTextField(labelWithString: suffix)
            suffixLabel.textColor = .tertiaryLabelColor
            suffixLabel.font = .systemFont(ofSize: 12)
            views.append(suffixLabel)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        return row
    }

    private func makeHint(_ text: String) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spacer.widthAnchor.constraint(equalToConstant: labelWidth)
        ])

        let hint = NSTextField(wrappingLabelWithString: text)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 260

        let row = NSStackView(views: [spacer, hint])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        return row
    }

    private func configureField(_ field: NSTextField, action: Selector) {
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 56)
        ])
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.target = self
        field.action = action
    }

    private func configureStepper(_ stepper: NSStepper, min: Double, max: Double, increment: Double) {
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = increment
        stepper.valueWraps = false
    }

    private func makeSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sep.widthAnchor.constraint(greaterThanOrEqualToConstant: 400)
        ])
        return sep
    }
}

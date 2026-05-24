import Foundation

@MainActor
@Observable
final class TerminalSettingsStore {
    static let shared = TerminalSettingsStore()

    private let defaults: UserDefaults
    @ObservationIgnored private var applyTask: Task<Void, Never>?

    var shellIntegrationMode: String { didSet { saveOption(shellIntegrationMode, key: "shellIntegrationMode") } }
    var shellCursorEnabled: Bool { didSet { saveBool(shellCursorEnabled, key: "shellCursorEnabled") } }
    var shellSSHIntegrationEnabled: Bool { didSet { saveBool(shellSSHIntegrationEnabled, key: "shellSSHIntegrationEnabled") } }
    var shellSudoIntegrationEnabled: Bool { didSet { saveBool(shellSudoIntegrationEnabled, key: "shellSudoIntegrationEnabled") } }
    var batteryOptimizedMode: Bool { didSet { saveBool(batteryOptimizedMode, key: "batteryOptimizedMode") } }
    var scrollSpeedProfile: String { didSet { saveOption(scrollSpeedProfile, key: "scrollSpeedProfile") } }
    var scrollbackProfile: String { didSet { saveOption(scrollbackProfile, key: "scrollbackProfile") } }
    var customScrollbackLimit: String { didSet { saveString(customScrollbackLimit, key: "customScrollbackLimit") } }
    var copyOnSelect: Bool { didSet { saveBool(copyOnSelect, key: "copyOnSelect") } }
    var clipboardRead: String { didSet { saveOption(clipboardRead, key: "clipboardRead") } }
    var clipboardWrite: String { didSet { saveOption(clipboardWrite, key: "clipboardWrite") } }
    var pasteProtectionEnabled: Bool { didSet { saveBool(pasteProtectionEnabled, key: "pasteProtectionEnabled") } }
    var linkPreviewsEnabled: Bool { didSet { saveBool(linkPreviewsEnabled, key: "linkPreviewsEnabled") } }
    var filePathActionsEnabled: Bool { didSet { saveBool(filePathActionsEnabled, key: "filePathActionsEnabled") } }
    var cursorClickToMoveEnabled: Bool { didSet { saveBool(cursorClickToMoveEnabled, key: "cursorClickToMoveEnabled") } }
    var optionAsAltMode: String { didSet { saveOption(optionAsAltMode, key: "optionAsAltMode") } }
    var mouseReportingEnabled: Bool { didSet { saveBool(mouseReportingEnabled, key: "mouseReportingEnabled") } }
    var imageStorageProfile: String { didSet { saveOption(imageStorageProfile, key: "imageStorageProfile") } }
    var telemetryEnabled: Bool { didSet { saveBool(telemetryEnabled, key: "telemetryEnabled") } }
    var quickTerminalPosition: String { didSet { saveString(quickTerminalPosition, key: "quickTerminalPosition") } }
    var quickTerminalSize: String { didSet { saveString(quickTerminalSize, key: "quickTerminalSize") } }
    var quickTerminalAutohide: Bool { didSet { saveBool(quickTerminalAutohide, key: "quickTerminalAutohide") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = TerminalSettingsSnapshot.default
        shellIntegrationMode = defaults.string(forKey: Self.key("shellIntegrationMode")) ?? fallback.shellIntegrationMode.rawValue
        shellCursorEnabled = Self.bool(defaults, "shellCursorEnabled", fallback.shellCursorEnabled)
        shellSSHIntegrationEnabled = Self.bool(defaults, "shellSSHIntegrationEnabled", fallback.shellSSHIntegrationEnabled)
        shellSudoIntegrationEnabled = Self.bool(defaults, "shellSudoIntegrationEnabled", fallback.shellSudoIntegrationEnabled)
        batteryOptimizedMode = Self.bool(defaults, "batteryOptimizedMode", fallback.batteryOptimizedMode)
        scrollSpeedProfile = defaults.string(forKey: Self.key("scrollSpeedProfile")) ?? fallback.scrollSpeedProfile.rawValue
        scrollbackProfile = defaults.string(forKey: Self.key("scrollbackProfile")) ?? fallback.scrollbackProfile.rawValue
        customScrollbackLimit = defaults.string(forKey: Self.key("customScrollbackLimit")) ?? String(fallback.customScrollbackLimit)
        copyOnSelect = Self.bool(defaults, "copyOnSelect", fallback.copyOnSelect)
        clipboardRead = defaults.string(forKey: Self.key("clipboardRead")) ?? fallback.clipboardRead.rawValue
        clipboardWrite = defaults.string(forKey: Self.key("clipboardWrite")) ?? fallback.clipboardWrite.rawValue
        pasteProtectionEnabled = Self.bool(defaults, "pasteProtectionEnabled", fallback.pasteProtectionEnabled)
        linkPreviewsEnabled = Self.bool(defaults, "linkPreviewsEnabled", fallback.linkPreviewsEnabled)
        filePathActionsEnabled = Self.bool(defaults, "filePathActionsEnabled", fallback.filePathActionsEnabled)
        cursorClickToMoveEnabled = Self.bool(defaults, "cursorClickToMoveEnabled", fallback.cursorClickToMoveEnabled)
        optionAsAltMode = defaults.string(forKey: Self.key("optionAsAltMode")) ?? fallback.optionAsAltMode.rawValue
        mouseReportingEnabled = Self.bool(defaults, "mouseReportingEnabled", fallback.mouseReportingEnabled)
        imageStorageProfile = defaults.string(forKey: Self.key("imageStorageProfile")) ?? fallback.imageStorageProfile.rawValue
        telemetryEnabled = Self.bool(defaults, "telemetryEnabled", fallback.telemetryEnabled)
        quickTerminalPosition = defaults.string(forKey: Self.key("quickTerminalPosition")) ?? fallback.quickTerminalPosition
        quickTerminalSize = defaults.string(forKey: Self.key("quickTerminalSize")) ?? fallback.quickTerminalSize
        quickTerminalAutohide = Self.bool(defaults, "quickTerminalAutohide", fallback.quickTerminalAutohide)
    }

    func snapshot() -> TerminalSettingsSnapshot {
        TerminalSettingsSnapshot(
            shellIntegrationMode: TerminalShellIntegrationMode(rawValue: shellIntegrationMode) ?? .detect,
            shellCursorEnabled: shellCursorEnabled,
            shellSSHIntegrationEnabled: shellSSHIntegrationEnabled,
            shellSudoIntegrationEnabled: shellSudoIntegrationEnabled,
            batteryOptimizedMode: batteryOptimizedMode,
            scrollSpeedProfile: TerminalScrollSpeedProfile(rawValue: scrollSpeedProfile) ?? .fast,
            scrollbackProfile: TerminalScrollbackProfile(rawValue: scrollbackProfile) ?? .balanced,
            customScrollbackLimit: Int(customScrollbackLimit) ?? 2_000_000,
            copyOnSelect: copyOnSelect,
            clipboardRead: TerminalClipboardAccess(rawValue: clipboardRead) ?? .ask,
            clipboardWrite: TerminalClipboardAccess(rawValue: clipboardWrite) ?? .allow,
            pasteProtectionEnabled: pasteProtectionEnabled,
            linkPreviewsEnabled: linkPreviewsEnabled,
            filePathActionsEnabled: filePathActionsEnabled,
            cursorClickToMoveEnabled: cursorClickToMoveEnabled,
            optionAsAltMode: TerminalOptionAsAltMode(rawValue: optionAsAltMode) ?? .always,
            mouseReportingEnabled: mouseReportingEnabled,
            imageStorageProfile: TerminalImageStorageProfile(rawValue: imageStorageProfile) ?? .balanced,
            telemetryEnabled: telemetryEnabled,
            quickTerminalPosition: quickTerminalPosition.isEmpty ? "bottom" : quickTerminalPosition,
            quickTerminalSize: quickTerminalSize.isEmpty ? "40%" : quickTerminalSize,
            quickTerminalAutohide: quickTerminalAutohide
        )
    }

    private func saveBool(_ value: Bool, key: String) {
        defaults.set(value, forKey: Self.key(key))
        apply()
    }

    private func saveOption(_ value: String, key: String) {
        defaults.set(value, forKey: Self.key(key))
        apply()
    }

    private func saveString(_ value: String, key: String) {
        defaults.set(value, forKey: Self.key(key))
        apply()
    }

    private func apply() {
        applyTask?.cancel()
        applyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard self != nil, !Task.isCancelled else { return }
            ThemeService.shared.applyDefaultThemeIfNeeded()
        }
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        guard defaults.object(forKey: Self.key(key)) != nil else { return fallback }
        return defaults.bool(forKey: Self.key(key))
    }

    private static func key(_ name: String) -> String {
        "kaji.terminal.\(name)"
    }
}

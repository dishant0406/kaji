import Foundation

struct TerminalSettingsSnapshot: Equatable {
    let shellIntegrationMode: TerminalShellIntegrationMode
    let shellCursorEnabled: Bool
    let shellSSHIntegrationEnabled: Bool
    let shellSudoIntegrationEnabled: Bool
    let batteryOptimizedMode: Bool
    let scrollSpeedProfile: TerminalScrollSpeedProfile
    let scrollbackProfile: TerminalScrollbackProfile
    let customScrollbackLimit: Int
    let copyOnSelect: Bool
    let clipboardRead: TerminalClipboardAccess
    let clipboardWrite: TerminalClipboardAccess
    let pasteProtectionEnabled: Bool
    let linkPreviewsEnabled: Bool
    let filePathActionsEnabled: Bool
    let cursorClickToMoveEnabled: Bool
    let optionAsAltMode: TerminalOptionAsAltMode
    let mouseReportingEnabled: Bool
    let imageStorageProfile: TerminalImageStorageProfile
    let telemetryEnabled: Bool
    let quickTerminalPosition: String
    let quickTerminalSize: String
    let quickTerminalAutohide: Bool

    static let `default` = TerminalSettingsSnapshot(
        shellIntegrationMode: .detect,
        shellCursorEnabled: true,
        shellSSHIntegrationEnabled: true,
        shellSudoIntegrationEnabled: false,
        batteryOptimizedMode: false,
        scrollSpeedProfile: .fast,
        scrollbackProfile: .balanced,
        customScrollbackLimit: 2_000_000,
        copyOnSelect: false,
        clipboardRead: .ask,
        clipboardWrite: .allow,
        pasteProtectionEnabled: true,
        linkPreviewsEnabled: true,
        filePathActionsEnabled: true,
        cursorClickToMoveEnabled: true,
        optionAsAltMode: .always,
        mouseReportingEnabled: true,
        imageStorageProfile: .balanced,
        telemetryEnabled: true,
        quickTerminalPosition: "bottom",
        quickTerminalSize: "40%",
        quickTerminalAutohide: true
    )
}

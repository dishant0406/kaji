import Foundation

struct TerminalSettingsSnapshot: Equatable {
    let shellIntegrationMode: TerminalShellIntegrationMode
    let shellCursorEnabled: Bool
    let shellSSHIntegrationEnabled: Bool
    let shellSudoIntegrationEnabled: Bool
    let batteryOptimizedMode: Bool
    let fontFamily: String
    let fontSize: Double
    let lineHeight: Double
    let paddingX: Double
    let paddingY: Double
    let cursorStyle: TerminalCursorStyle
    let cursorBlink: Bool
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
    let glassBackgroundEnabled: Bool
    let glassBackgroundOpacity: Double
    let glassBlurMode: TerminalGlassBlurMode

    static let `default` = TerminalSettingsSnapshot(
        shellIntegrationMode: .detect,
        shellCursorEnabled: true,
        shellSSHIntegrationEnabled: true,
        shellSudoIntegrationEnabled: false,
        batteryOptimizedMode: false,
        fontFamily: TerminalBundledFont.familyName,
        fontSize: 13,
        lineHeight: 1.2,
        paddingX: 12,
        paddingY: 8,
        cursorStyle: .line,
        cursorBlink: false,
        scrollSpeedProfile: .fast,
        scrollbackProfile: .balanced,
        customScrollbackLimit: TerminalScrollbackProfile.defaultLimit,
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
        quickTerminalAutohide: true,
        glassBackgroundEnabled: false,
        glassBackgroundOpacity: 0.94,
        glassBlurMode: .regular
    )
}

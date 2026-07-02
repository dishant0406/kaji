@testable import Kaji

extension TerminalSettingsSnapshot {
    static func test(
        shellIntegrationMode: TerminalShellIntegrationMode = .detect,
        fontFamily: String = TerminalBundledFont.familyName,
        fontSize: Double = 13,
        lineHeight: Double = 1.2,
        paddingX: Double = 12,
        paddingY: Double = 8,
        cursorStyle: TerminalCursorStyle = .line,
        cursorBlink: Bool = false
    ) -> TerminalSettingsSnapshot {
        TerminalSettingsSnapshot(
            shellIntegrationMode: shellIntegrationMode,
            shellCursorEnabled: true,
            shellSSHIntegrationEnabled: true,
            shellSudoIntegrationEnabled: false,
            batteryOptimizedMode: false,
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineHeight: lineHeight,
            paddingX: paddingX,
            paddingY: paddingY,
            cursorStyle: cursorStyle,
            cursorBlink: cursorBlink,
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
            quickTerminalAutohide: true,
            glassBackgroundEnabled: false,
            glassBackgroundOpacity: 0.94,
            glassBlurMode: .regular
        )
    }
}

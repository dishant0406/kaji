import Testing

@testable import Kaji

struct GhosttyTerminalConfigDefaultsTests {
    @Test
    func buildsDocumentedTerminalDefaults() {
        let lines = GhosttyTerminalConfigDefaults.lines()

        #expect(lines.contains("shell-integration = detect"))
        #expect(lines.contains("scrollback-limit = 2000000"))
        #expect(lines.contains("mouse-scroll-multiplier = precision:3,discrete:5"))
        #expect(lines.contains("image-storage-limit = 335544320"))
        #expect(lines.contains("copy-on-select = false"))
        #expect(lines.contains("clipboard-read = ask"))
        #expect(lines.contains("clipboard-write = allow"))
        #expect(lines.contains("clipboard-paste-bracketed-safe = false"))
        #expect(lines.contains("link-url = true"))
        #expect(lines.contains("macos-option-as-alt = true"))
    }

    @Test
    func buildsBatteryAndSecurityOverrides() {
        var settings = TerminalSettingsSnapshot.default
        settings = TerminalSettingsSnapshot(
            shellIntegrationMode: .disabled,
            shellCursorEnabled: false,
            shellSSHIntegrationEnabled: false,
            shellSudoIntegrationEnabled: false,
            batteryOptimizedMode: true,
            scrollSpeedProfile: .veryFast,
            scrollbackProfile: .custom,
            customScrollbackLimit: 60_000_000,
            copyOnSelect: true,
            clipboardRead: .deny,
            clipboardWrite: .deny,
            pasteProtectionEnabled: false,
            linkPreviewsEnabled: false,
            filePathActionsEnabled: false,
            cursorClickToMoveEnabled: false,
            optionAsAltMode: .never,
            mouseReportingEnabled: false,
            imageStorageProfile: .disabled,
            telemetryEnabled: false,
            quickTerminalPosition: "top",
            quickTerminalSize: "30%",
            quickTerminalAutohide: false,
            glassBackgroundEnabled: false,
            glassBackgroundOpacity: 0.94,
            glassBlurMode: .regular
        )

        let lines = GhosttyTerminalConfigDefaults.lines(settings: settings)

        #expect(lines.contains("shell-integration = none"))
        #expect(lines.contains("shell-integration-features = false"))
        #expect(lines.contains("scrollback-limit = 50000000"))
        #expect(lines.contains("mouse-scroll-multiplier = precision:5,discrete:8"))
        #expect(lines.contains("macos-option-as-alt = false"))
        #expect(lines.contains("copy-on-select = clipboard"))
        #expect(lines.contains("clipboard-read = deny"))
        #expect(lines.contains("clipboard-paste-bracketed-safe = true"))
        #expect(lines.contains("custom-shader-animation = false"))
    }

    @Test
    func emitsGlassBackgroundOnlyWhenSupported() {
        var settings = TerminalSettingsSnapshot.default
        settings = TerminalSettingsSnapshot(
            shellIntegrationMode: settings.shellIntegrationMode,
            shellCursorEnabled: settings.shellCursorEnabled,
            shellSSHIntegrationEnabled: settings.shellSSHIntegrationEnabled,
            shellSudoIntegrationEnabled: settings.shellSudoIntegrationEnabled,
            batteryOptimizedMode: settings.batteryOptimizedMode,
            scrollSpeedProfile: settings.scrollSpeedProfile,
            scrollbackProfile: settings.scrollbackProfile,
            customScrollbackLimit: settings.customScrollbackLimit,
            copyOnSelect: settings.copyOnSelect,
            clipboardRead: settings.clipboardRead,
            clipboardWrite: settings.clipboardWrite,
            pasteProtectionEnabled: settings.pasteProtectionEnabled,
            linkPreviewsEnabled: settings.linkPreviewsEnabled,
            filePathActionsEnabled: settings.filePathActionsEnabled,
            cursorClickToMoveEnabled: settings.cursorClickToMoveEnabled,
            optionAsAltMode: settings.optionAsAltMode,
            mouseReportingEnabled: settings.mouseReportingEnabled,
            imageStorageProfile: settings.imageStorageProfile,
            telemetryEnabled: settings.telemetryEnabled,
            quickTerminalPosition: settings.quickTerminalPosition,
            quickTerminalSize: settings.quickTerminalSize,
            quickTerminalAutohide: settings.quickTerminalAutohide,
            glassBackgroundEnabled: true,
            glassBackgroundOpacity: 0.82,
            glassBlurMode: .clear
        )

        let supportedLines = GhosttyTerminalConfigDefaults.lines(settings: settings, supportsLiquidGlass: true)
        let unsupportedLines = GhosttyTerminalConfigDefaults.lines(settings: settings, supportsLiquidGlass: false)

        #expect(supportedLines.contains("background-opacity = 0.82"))
        #expect(supportedLines.contains("background-blur = macos-glass-clear"))
        #expect(supportedLines.contains("background-opacity-cells = false"))
        #expect(!unsupportedLines.contains { $0.hasPrefix("background-opacity = ") })
        #expect(!unsupportedLines.contains { $0.hasPrefix("background-blur = ") })
        #expect(!unsupportedLines.contains("background-opacity-cells = false"))
    }
}

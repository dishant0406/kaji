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
            quickTerminalAutohide: false
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
}

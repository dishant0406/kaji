import SwiftUI

struct TerminalSettingsView: View {
    @State private var settings = TerminalSettingsStore.shared
    @State private var monoFonts: [String] = []

    var body: some View {
        SettingsContainer {
            appearanceSection
            shellSection
            performanceSection
            securitySection
            quickTerminalSection
            graphicsSection
            TerminalConfigDiagnosticsSection()
        }
        .task {
            TerminalBundledFont.registerIfNeeded()
            monoFonts = AppTypographySettings.availableMonospacedFonts
        }
    }

    private var appearanceSection: some View {
        SettingsSection("Terminal Appearance") {
            picker("Font", selection: $settings.fontFamily, options: fontOptions)
            SettingsSliderRow(
                label: "Font size",
                value: $settings.fontSize,
                range: 9 ... 36,
                valueText: { value in "\(Int(value.rounded())) px" }
            )
            SettingsSliderRow(
                label: "Line height",
                value: $settings.lineHeight,
                range: 0.9 ... 2,
                valueText: { value in String(format: "%.2fx", value) }
            )
            SettingsSliderRow(
                label: "Horizontal padding",
                value: $settings.paddingX,
                range: 0 ... 48,
                valueText: { value in "\(Int(value.rounded())) px" }
            )
            SettingsSliderRow(
                label: "Vertical padding",
                value: $settings.paddingY,
                range: 0 ... 48,
                valueText: { value in "\(Int(value.rounded())) px" }
            )
            picker("Cursor", selection: $settings.cursorStyle, options: TerminalCursorStyle.allCases.map(\.rawValue))
            SettingsToggleRow(label: "Blink cursor", isOn: $settings.cursorBlink)
        }
    }

    private var fontOptions: [String] {
        TerminalFontOptions.options(current: settings.fontFamily, installedFonts: monoFonts)
    }

    private var shellSection: some View {
        SettingsSection("Shell Integration") {
            picker("Mode", selection: $settings.shellIntegrationMode, options: TerminalShellIntegrationMode.allCases.map(\.rawValue))
            SettingsToggleRow(label: "Prompt cursor", isOn: $settings.shellCursorEnabled)
            SettingsToggleRow(label: "SSH compatibility", isOn: $settings.shellSSHIntegrationEnabled)
            SettingsToggleRow(label: "Sudo terminfo wrapper", isOn: $settings.shellSudoIntegrationEnabled)
            SettingsToggleRow(label: "Option-click moves cursor", isOn: $settings.cursorClickToMoveEnabled)
            picker("Option key", selection: $settings.optionAsAltMode, options: TerminalOptionAsAltMode.allCases.map(\.rawValue))
            SettingsToggleRow(label: "Mouse reporting", isOn: $settings.mouseReportingEnabled)
        }
    }

    private var performanceSection: some View {
        SettingsSection("Performance") {
            SettingsToggleRow(label: "Battery optimized mode", isOn: $settings.batteryOptimizedMode)
            picker("Scroll speed", selection: $settings.scrollSpeedProfile, options: TerminalScrollSpeedProfile.allCases.map(\.rawValue))
            picker("Scrollback", selection: $settings.scrollbackProfile, options: TerminalScrollbackProfile.allCases.map(\.rawValue))
            SettingsInputRow(
                label: "Custom scrollback lines",
                placeholder: "10000",
                text: $settings.customScrollbackLimit,
                monospaced: true
            )
            SettingsToggleRow(label: "Telemetry", isOn: $settings.telemetryEnabled)
        }
    }

    private var securitySection: some View {
        SettingsSection("Clipboard and Links") {
            SettingsToggleRow(label: "Copy on select", isOn: $settings.copyOnSelect)
            picker("Clipboard read", selection: $settings.clipboardRead, options: TerminalClipboardAccess.allCases.map(\.rawValue))
            picker("Clipboard write", selection: $settings.clipboardWrite, options: TerminalClipboardAccess.allCases.map(\.rawValue))
            SettingsToggleRow(label: "Bracketed paste protection", isOn: $settings.pasteProtectionEnabled)
            SettingsToggleRow(label: "Link previews", isOn: $settings.linkPreviewsEnabled)
            SettingsToggleRow(label: "File path actions", isOn: $settings.filePathActionsEnabled)
        }
    }

    private var quickTerminalSection: some View {
        SettingsSection("Quick Terminal") {
            picker("Position", selection: $settings.quickTerminalPosition, options: ["top", "bottom", "left", "right", "center"])
            SettingsInputRow(
                label: "Size",
                placeholder: "40%",
                text: $settings.quickTerminalSize,
                monospaced: true
            )
            SettingsToggleRow(label: "Autohide", isOn: $settings.quickTerminalAutohide)
        }
    }

    private var graphicsSection: some View {
        SettingsSection("Graphics", showsDivider: false) {
            picker(
                "Image protocol memory",
                selection: $settings.imageStorageProfile,
                options: TerminalImageStorageProfile.allCases.map(\.rawValue)
            )
            if AppearanceCapabilities.supportsLiquidGlass {
                SettingsDetailToggleRow(
                    label: "Glass terminal background",
                    detail: "Uses Termy's native macOS glass blur. New terminals may be required.",
                    isOn: $settings.glassBackgroundEnabled
                )
                SettingsSliderRow(
                    label: "Glass opacity",
                    value: $settings.glassBackgroundOpacity,
                    range: 0.72 ... 1,
                    isEnabled: settings.glassBackgroundEnabled,
                    valueText: { value in
                        "\(Int((value * 100).rounded()))%"
                    }
                )
                picker(
                    "Glass blur",
                    selection: $settings.glassBlurMode,
                    options: TerminalGlassBlurMode.allCases.map(\.rawValue)
                )
                .disabled(!settings.glassBackgroundEnabled)
            }
        }
    }

    private func picker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        SettingsRow(label) {
            KajiSelect(
                options: options.map { KajiSelectOption(id: $0, title: $0, value: $0) },
                selection: selection,
                width: SettingsMetrics.controlWidth
            )
        }
    }
}

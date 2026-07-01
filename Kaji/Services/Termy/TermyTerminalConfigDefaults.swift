import Foundation

enum TermyTerminalConfigDefaults {
    static let managedKeys = [
        "shell_integration_enabled",
        "tab_title_shell_integration",
        "progress_indicator_enabled",
        "cursor_style",
        "cursor_blink",
        "mouse_scroll_multiplier",
        "scrollback_history",
        "copy_on_select",
        "copy_on_select_toast",
        "background_opacity",
        "background_blur",
        "background_opacity_cells",
    ]

    static func lines(
        settings: TerminalSettingsSnapshot = .default,
        supportsLiquidGlass: Bool = AppearanceCapabilities.supportsLiquidGlass
    ) -> [String] {
        var lines = [
            "shell_integration_enabled = \(settings.shellIntegrationMode != .disabled)",
            "tab_title_shell_integration = \(settings.shellIntegrationMode != .disabled)",
            "progress_indicator_enabled = true",
            "cursor_style = line",
            "cursor_blink = false",
            "mouse_scroll_multiplier = \(settings.scrollSpeedProfile.termyMultiplier)",
            "scrollback_history = \(settings.scrollbackProfile.limit(customValue: settings.customScrollbackLimit))",
            "copy_on_select = \(settings.copyOnSelect)",
            "copy_on_select_toast = false",
        ]
        if settings.glassBackgroundEnabled, supportsLiquidGlass {
            lines.append("background_opacity = \(settings.glassBackgroundOpacity)")
            lines.append("background_blur = true")
            lines.append("background_opacity_cells = false")
        }
        return lines
    }
}

private extension TerminalScrollSpeedProfile {
    var termyMultiplier: Double {
        switch self {
        case .native: 1
        case .fast: 3
        case .veryFast: 5
        }
    }
}

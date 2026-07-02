import Foundation

enum TermyTerminalConfigDefaults {
    static let managedKeys = [
        "shell_integration_enabled",
        "tab_title_shell_integration",
        "progress_indicator_enabled",
        "term",
        "colorterm",
        "cursor_style",
        "cursor_blink",
        "padding_x",
        "padding_y",
        "mouse_scroll_multiplier",
        "scrollback_history",
        "inactive_tab_scrollback",
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
            "term = xterm-256color",
            "colorterm = truecolor",
            "cursor_style = \(settings.cursorStyle.termyValue)",
            "cursor_blink = \(settings.cursorBlink)",
            "padding_x = \(format(settings.paddingX))",
            "padding_y = \(format(settings.paddingY))",
            "mouse_scroll_multiplier = \(settings.scrollSpeedProfile.termyMultiplier)",
            "scrollback_history = \(settings.scrollbackProfile.limit(customValue: settings.customScrollbackLimit))",
            "inactive_tab_scrollback = \(settings.scrollbackProfile.inactiveLimit(customValue: settings.customScrollbackLimit))",
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

    private static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
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

import Foundation

enum GhosttyTerminalConfigDefaults {
    static let managedKeys = [
        "shell-integration",
        "shell-integration-features",
        "cursor-style",
        "cursor-style-blink",
        "cursor-click-to-move",
        "macos-option-as-alt",
        "mouse-reporting",
        "mouse-scroll-multiplier",
        "scrollback-limit",
        "image-storage-limit",
        "copy-on-select",
        "clipboard-read",
        "clipboard-write",
        "clipboard-paste-bracketed-safe",
        "link-url",
        "quick-terminal-position",
        "quick-terminal-size",
        "quick-terminal-autohide",
        "background-opacity",
        "background-blur",
        "background-opacity-cells",
        "custom-shader-animation",
    ]

    static func lines(
        settings: TerminalSettingsSnapshot = .default,
        supportsLiquidGlass: Bool = AppearanceCapabilities.supportsLiquidGlass
    ) -> [String] {
        var lines = [
            "shell-integration = \(settings.shellIntegrationMode.ghosttyValue)",
            "shell-integration-features = \(shellFeatures(settings))",
            "cursor-style = bar",
            "cursor-style-blink = false",
            "cursor-click-to-move = \(settings.cursorClickToMoveEnabled)",
            "macos-option-as-alt = \(settings.optionAsAltMode.ghosttyValue)",
            "mouse-reporting = \(settings.mouseReportingEnabled)",
            "mouse-scroll-multiplier = \(settings.scrollSpeedProfile.ghosttyValue)",
            "scrollback-limit = \(settings.scrollbackProfile.limit(customValue: settings.customScrollbackLimit))",
            "image-storage-limit = \(settings.imageStorageProfile.byteLimit)",
            "copy-on-select = \(settings.copyOnSelect ? "clipboard" : "false")",
            "clipboard-read = \(settings.clipboardRead.ghosttyValue)",
            "clipboard-write = \(settings.clipboardWrite.ghosttyValue)",
            "clipboard-paste-bracketed-safe = \(!settings.pasteProtectionEnabled)",
            "link-url = \(settings.linkPreviewsEnabled)",
            "quick-terminal-position = \(settings.quickTerminalPosition)",
            "quick-terminal-size = \(settings.quickTerminalSize)",
            "quick-terminal-autohide = \(settings.quickTerminalAutohide)",
        ]
        if settings.batteryOptimizedMode {
            lines.append("custom-shader-animation = false")
        }
        if settings.glassBackgroundEnabled, supportsLiquidGlass {
            lines.append("background-opacity = \(settings.glassBackgroundOpacity)")
            lines.append("background-blur = \(settings.glassBlurMode.ghosttyValue)")
            lines.append("background-opacity-cells = false")
        }
        return lines
    }

    private static func shellFeatures(_ settings: TerminalSettingsSnapshot) -> String {
        guard settings.shellIntegrationMode != .disabled else { return "false" }
        var features: [String] = [
            settings.shellCursorEnabled ? "cursor" : "no-cursor",
            settings.shellSudoIntegrationEnabled ? "sudo" : "no-sudo",
            "title",
            "path",
        ]
        features.append(settings.shellSSHIntegrationEnabled ? "ssh-env,ssh-terminfo" : "no-ssh-env,no-ssh-terminfo")
        return features.joined(separator: ",")
    }
}

import Foundation

enum GhosttyInteractionDefaults {
    private static let shellIntegrationKey = "shell-integration"
    private static let cursorStyleKey = "cursor-style"
    private static let cursorBlinkKey = "cursor-style-blink"
    private static let cursorClickToMoveKey = "cursor-click-to-move"

    static func linesIfMissing(in lines: [String]) -> [String] {
        var defaults: [String] = []

        if !hasConfigLine(for: shellIntegrationKey, in: lines) {
            defaults.append("shell-integration = detect")
        }

        if !hasConfigLine(for: cursorStyleKey, in: lines) {
            defaults.append("cursor-style = bar")
        }

        if !hasConfigLine(for: cursorBlinkKey, in: lines) {
            defaults.append("cursor-style-blink = true")
        }

        if !hasConfigLine(for: cursorClickToMoveKey, in: lines) {
            defaults.append("cursor-click-to-move = true")
        }

        return defaults
    }

    private static func hasConfigLine(for key: String, in lines: [String]) -> Bool {
        lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { return false }
            let suffix = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            return suffix.hasPrefix("=")
        }
    }
}

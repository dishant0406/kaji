import Foundation

enum GhosttyInteractionDefaults {
    static func linesIfMissing(in lines: [String]) -> [String] {
        GhosttyTerminalConfigDefaults.lines().filter { defaultLine in
            let key = defaultLine.components(separatedBy: "=")[0].trimmingCharacters(in: .whitespaces)
            let keys = [
                "shell-integration",
                "shell-integration-features",
                "cursor-style",
                "cursor-style-blink",
                "cursor-click-to-move",
                "macos-option-as-alt",
            ]
            guard keys.contains(key) else { return false }
            return !lines.contains { hasConfigLine($0, for: key) }
        }
    }

    private static func hasConfigLine(_ line: String, for key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(key) else { return false }
        let suffix = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return suffix.hasPrefix("=")
    }
}

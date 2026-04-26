import Foundation

enum GhosttyTypographyDefaults {
    private static let fontSizeKey = "font-size"
    private static let fontFamilyKey = "font-family"

    static func linesIfMissing(in lines: [String]) -> [String] {
        var defaults: [String] = []

        if !hasConfigLine(for: fontSizeKey, in: lines) {
            defaults.append("font-size = 15")
        }

        if !hasConfigLine(for: fontFamilyKey, in: lines) {
            defaults.append("font-family = \"SF Mono\"")
            defaults.append("font-family = \"Menlo\"")
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

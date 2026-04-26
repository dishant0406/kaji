import Foundation

enum GhosttyTypographyDefaults {
    static let managedKeys = ["font-size", "font-family"]

    static func lines(fontSize: CGFloat, fontFamily: String) -> [String] {
        let normalizedFamily = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFamily = normalizedFamily.isEmpty ? AppTypographySettings.defaultFontFamily : normalizedFamily
        let resolvedSize = max(10, min(36, fontSize))

        if resolvedFamily == "Menlo" {
            return [
                "font-size = \(Int(resolvedSize.rounded()))",
                "font-family = \"Menlo\"",
            ]
        }

        return [
            "font-size = \(Int(resolvedSize.rounded()))",
            "font-family = \"\(resolvedFamily)\"",
            "font-family = \"Menlo\"",
        ]
    }
}

import Foundation

enum TermyTypographyDefaults {
    static let managedKeys = ["font_family", "ui_font_family", "font_size", "line_height"]

    static func lines(fontSize: CGFloat, fontFamily: String) -> [String] {
        let normalizedFamily = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFamily = normalizedFamily.isEmpty ? AppTypographySettings.defaultFontFamily : normalizedFamily
        let resolvedSize = max(10, min(36, fontSize))
        return [
            "font_family = \"\(resolvedFamily)\"",
            "ui_font_family = \"\(resolvedFamily)\"",
            "font_size = \(Int(resolvedSize.rounded()))",
            "line_height = 1.2",
        ]
    }
}

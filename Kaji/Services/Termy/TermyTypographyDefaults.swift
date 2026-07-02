import Foundation

enum TermyTypographyDefaults {
    static let managedKeys = ["font_family", "ui_font_family", "font_size", "line_height"]

    static func lines(settings: TerminalSettingsSnapshot = .default) -> [String] {
        let normalizedFamily = settings.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFamily = normalizedFamily.isEmpty ? TerminalSettingsSnapshot.default.fontFamily : normalizedFamily
        let resolvedSize = max(9, min(36, settings.fontSize))
        let resolvedLineHeight = max(0.9, min(2, settings.lineHeight))
        return [
            "font_family = \"\(escaped(resolvedFamily))\"",
            "ui_font_family = \"\(escaped(resolvedFamily))\"",
            "font_size = \(format(resolvedSize))",
            "line_height = \(format(resolvedLineHeight))",
        ]
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.2f", rounded).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }
}

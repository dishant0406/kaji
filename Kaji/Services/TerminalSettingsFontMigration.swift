import Foundation

enum TerminalSettingsFontMigration {
    private static let fontKey = "kaji.terminal.fontFamily"
    private static let migrationKey = "kaji.terminal.promptGlyphFontMigration"

    static func resolvedFontFamily(defaults: UserDefaults, fallback: String) -> String {
        let stored = defaults.string(forKey: fontKey)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !defaults.bool(forKey: migrationKey) else {
            return stored?.isEmpty == false ? stored ?? fallback : fallback
        }

        defaults.set(true, forKey: migrationKey)

        guard let stored, !stored.isEmpty else {
            defaults.set(fallback, forKey: fontKey)
            return fallback
        }

        guard stored == TerminalBundledFont.legacyDefaultFamily else {
            return stored
        }

        defaults.set(fallback, forKey: fontKey)
        return fallback
    }
}

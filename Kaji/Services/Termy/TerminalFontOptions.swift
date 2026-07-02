import Foundation

enum TerminalFontOptions {
    static func options(current: String, installedFonts: [String]) -> [String] {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var options = [String]()

        for font in [TerminalBundledFont.familyName] + installedFonts + [current] {
            let trimmed = font.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            options.append(trimmed)
        }

        return options
    }
}

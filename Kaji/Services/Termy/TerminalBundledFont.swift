import AppKit
import CoreText
import Foundation

enum TerminalBundledFont {
    static let familyName = "JetBrainsMono Nerd Font Mono"
    static let legacyDefaultFamily = "SF Mono"
    static let resourceSubdirectory = "Fonts/Terminal"

    private static let fontFileNames = [
        "JetBrainsMonoNerdFontMono-Regular",
        "JetBrainsMonoNerdFontMono-Bold",
        "JetBrainsMonoNerdFontMono-SemiBold",
        "JetBrainsMonoNerdFontMono-Italic",
        "JetBrainsMonoNerdFontMono-BoldItalic",
    ]

    private static let promptGlyphScalars: [UniChar] = [
        0xE0A0,
        0xE0B0,
        0xE0B1,
        0xF013,
        0xF015,
        0xF07C,
        0xF0E7,
    ]

    @discardableResult
    static func registerIfNeeded(bundle: Bundle = .appResources) -> Bool {
        if isAvailable() {
            return true
        }

        for fileName in fontFileNames {
            guard let url = fontURL(fileName: fileName, bundle: bundle) else {
                return false
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                _ = error?.takeRetainedValue()
            }
        }

        return isAvailable()
    }

    static func isAvailable(size: CGFloat = 13) -> Bool {
        NSFont(name: familyName, size: size) != nil
    }

    static func supportsPromptGlyphs(size: CGFloat = 13) -> Bool {
        guard isAvailable(size: size) else {
            return false
        }

        let font = CTFontCreateWithName(familyName as CFString, size, nil)
        var characters = promptGlyphScalars
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let mapped = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        return mapped && glyphs.allSatisfy { $0 != 0 }
    }

    private static func fontURL(fileName: String, bundle: Bundle) -> URL? {
        bundle.url(forResource: fileName, withExtension: "ttf", subdirectory: resourceSubdirectory)
            ?? bundle.url(forResource: fileName, withExtension: "ttf")
    }
}

import Foundation
import Testing

@testable import Droid

struct ThemeFileCodecTests {
    @Test
    func slugifiesNamesForThemeIdentifiers() {
        #expect(ThemeFileCodec.slugify(" Midnight Droid  ") == "midnight-droid")
        #expect(ThemeFileCodec.slugify("Ayu Dark++") == "ayu-dark")
    }

    @Test
    func normalizesDraftHexValues() {
        let draft = ThemeDraft(
            name: "Noir",
            slug: "noir",
            colors: ThemeColorSet(
                background: "101010",
                foreground: "#ffffff",
                cursorColor: "#ffc799",
                cursorText: "#101010",
                selectionBackground: "#2d2d2d",
                selectionForeground: "#ffffff",
                palette: ThemeDraft.droidDefaults.colors.palette.map { $0.lowercased() }
            )
        )

        let normalized = ThemeFileCodec.normalizedDraft(draft)

        #expect(normalized?.colors.background == "#101010")
        #expect(normalized?.colors.foreground == "#FFFFFF")
        #expect(normalized?.colors.palette.first == "#242424")
    }

    @Test
    func buildAndParseRoundTripPreservesMetadata() throws {
        let draft = ThemeDraft(
            name: "Noir Terminal",
            slug: "noir-terminal",
            colors: ThemeDraft.droidDefaults.colors
        )
        let content = try #require(ThemeFileCodec.buildContent(from: draft))
        let preview = try #require(
            ThemeFileCodec.parseThemeContent(
                content,
                identifier: "noir-terminal",
                source: .external
            )
        )

        #expect(preview.name == "Noir Terminal")
        #expect(preview.identifier == "noir-terminal")
        #expect(preview.draft.slug == "noir-terminal")
        #expect(preview.draft.colors.selectionBackground == "#2D2D2D")
    }

    @Test
    func uniqueSlugAppendsNumericSuffix() {
        let slug = ThemeFileCodec.uniqueSlug("droid", existing: ["droid", "droid-2"])
        #expect(slug == "droid-3")
    }
}

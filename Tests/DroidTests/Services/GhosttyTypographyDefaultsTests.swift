import Testing

@testable import Droid

struct GhosttyTypographyDefaultsTests {
    @Test
    func addsDefaultFontSizeAndFamiliesWhenMissing() {
        let defaults = GhosttyTypographyDefaults.linesIfMissing(in: [
            "background = #0F1419",
            "foreground = #E6E1CF",
        ])

        #expect(defaults == [
            "font-size = 15",
            "font-family = \"SF Mono\"",
            "font-family = \"Menlo\"",
        ])
    }

    @Test
    func keepsExistingFontSettingsUntouched() {
        let defaults = GhosttyTypographyDefaults.linesIfMissing(in: [
            "font-size = 17",
            "font-family = \"JetBrains Mono\"",
        ])

        #expect(defaults.isEmpty)
    }

    @Test
    func fillsOnlyTheMissingTypographyKey() {
        let defaults = GhosttyTypographyDefaults.linesIfMissing(in: [
            "font-size = 16",
        ])

        #expect(defaults == [
            "font-family = \"SF Mono\"",
            "font-family = \"Menlo\"",
        ])
    }
}

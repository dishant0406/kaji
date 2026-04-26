import Testing

@testable import Droid

struct GhosttyTypographyDefaultsTests {
    @Test
    func buildsConfiguredFontSizeAndFamilyLines() {
        let lines = GhosttyTypographyDefaults.lines(fontSize: 16, fontFamily: "JetBrains Mono")

        #expect(lines == [
            "font-size = 16",
            "font-family = \"JetBrains Mono\"",
            "font-family = \"Menlo\"",
        ])
    }

    @Test
    func trimsEmptyFamilyToAppDefault() {
        let lines = GhosttyTypographyDefaults.lines(fontSize: 15, fontFamily: "   ")

        #expect(lines == [
            "font-size = 15",
            "font-family = \"SF Mono\"",
            "font-family = \"Menlo\"",
        ])
    }

    @Test
    func avoidsDuplicatingMenloFallback() {
        let lines = GhosttyTypographyDefaults.lines(fontSize: 14, fontFamily: "Menlo")

        #expect(lines == [
            "font-size = 14",
            "font-family = \"Menlo\"",
        ])
    }
}

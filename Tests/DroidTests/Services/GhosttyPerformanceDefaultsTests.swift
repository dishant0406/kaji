import Testing

@testable import Droid

struct GhosttyPerformanceDefaultsTests {
    @Test
    func addsScrollbackLimitWhenMissing() {
        let defaults = GhosttyPerformanceDefaults.linesIfMissing(in: [
            "theme = \"Droid\"",
            "font-size = 16",
        ])

        #expect(defaults == [
            "scrollback-limit = 5000000",
        ])
    }

    @Test
    func preservesExistingScrollbackLimit() {
        let defaults = GhosttyPerformanceDefaults.linesIfMissing(in: [
            "scrollback-limit = 25000000",
        ])

        #expect(defaults.isEmpty)
    }
}

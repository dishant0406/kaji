import Testing

@testable import Kaji

struct GhosttyPerformanceDefaultsTests {
    @Test
    func addsScrollbackLimitWhenMissing() {
        let defaults = GhosttyPerformanceDefaults.linesIfMissing(in: [
            "theme = \"Kaji\"",
            "font-size = 16",
        ])

        #expect(defaults == [
            "mouse-scroll-multiplier = precision:3,discrete:5",
            "scrollback-limit = 2000000",
        ])
    }

    @Test
    func preservesExistingPerformanceSettings() {
        let defaults = GhosttyPerformanceDefaults.linesIfMissing(in: [
            "mouse-scroll-multiplier = precision:1,discrete:3",
            "scrollback-limit = 25000000",
        ])

        #expect(defaults.isEmpty)
    }

    @Test
    func fillsOnlyMissingPerformanceSettings() {
        let defaults = GhosttyPerformanceDefaults.linesIfMissing(in: [
            "scrollback-limit = 25000000",
        ])

        #expect(defaults == [
            "mouse-scroll-multiplier = precision:3,discrete:5",
        ])
    }
}

import Testing

@testable import Droid

struct GhosttyInteractionDefaultsTests {
    @Test
    func addsEditorLikeDefaultsWhenMissing() {
        let defaults = GhosttyInteractionDefaults.linesIfMissing(in: [
            "background = #0F1419",
            "foreground = #E6E1CF",
        ])

        #expect(defaults == [
            "shell-integration = detect",
            "cursor-style = bar",
            "cursor-style-blink = true",
            "cursor-click-to-move = true",
        ])
    }

    @Test
    func keepsExistingInteractionSettingsUntouched() {
        let defaults = GhosttyInteractionDefaults.linesIfMissing(in: [
            "shell-integration = none",
            "cursor-style = block",
            "cursor-style-blink = false",
            "cursor-click-to-move = false",
        ])

        #expect(defaults.isEmpty)
    }

    @Test
    func fillsOnlyMissingInteractionKeys() {
        let defaults = GhosttyInteractionDefaults.linesIfMissing(in: [
            "cursor-style = underline",
        ])

        #expect(defaults == [
            "shell-integration = detect",
            "cursor-style-blink = true",
            "cursor-click-to-move = true",
        ])
    }
}

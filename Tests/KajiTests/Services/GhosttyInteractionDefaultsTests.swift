import Testing

@testable import Kaji

struct GhosttyInteractionDefaultsTests {
    @Test
    func addsEditorLikeDefaultsWhenMissing() {
        let defaults = GhosttyInteractionDefaults.linesIfMissing(in: [
            "background = #0F1419",
            "foreground = #E6E1CF",
        ])

        #expect(defaults == [
            "shell-integration = detect",
            "shell-integration-features = cursor,no-sudo,title,path,ssh-env,ssh-terminfo",
            "cursor-style = bar",
            "cursor-style-blink = false",
            "cursor-click-to-move = true",
            "macos-option-as-alt = true",
        ])
    }

    @Test
    func keepsExistingInteractionSettingsUntouched() {
        let defaults = GhosttyInteractionDefaults.linesIfMissing(in: [
            "shell-integration = none",
            "cursor-style = block",
            "cursor-style-blink = false",
            "cursor-click-to-move = false",
            "macos-option-as-alt = false",
            "shell-integration-features = false",
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
            "shell-integration-features = cursor,no-sudo,title,path,ssh-env,ssh-terminfo",
            "cursor-style-blink = false",
            "cursor-click-to-move = true",
            "macos-option-as-alt = true",
        ])
    }
}

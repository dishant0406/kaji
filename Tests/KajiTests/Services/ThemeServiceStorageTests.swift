import Testing

@testable import Kaji

struct ThemeServiceStorageTests {
    @Test
    @MainActor
    func addsTerminalWritingDefaultsToGeneratedConfig() {
        let preview = ThemePreview(
            identifier: "noir",
            name: "Noir",
            source: .external,
            draft: ThemeDraft(name: "Noir", slug: "noir", colors: ThemeDraft.kajiDefaults.colors),
            content: ""
        )

        let content = ThemeService.updatedConfigContent(
            from: "font-size = 16",
            themeIdentifier: preview.identifier,
            theme: preview,
            typographyLines: GhosttyTypographyDefaults.lines(fontSize: 18, fontFamily: "JetBrains Mono"),
            terminalLines: GhosttyTerminalConfigDefaults.lines()
        )

        #expect(content.contains("theme = \"noir\""))
        #expect(content.contains("font-size = 18"))
        #expect(content.contains("font-family = \"JetBrains Mono\""))
        #expect(content.contains("cursor-style = bar"))
        #expect(content.contains("cursor-style-blink = false"))
        #expect(content.contains("cursor-click-to-move = true"))
        #expect(content.contains("macos-option-as-alt = true"))
        #expect(content.contains("shell-integration = detect"))
        #expect(content.contains("mouse-scroll-multiplier = precision:3,discrete:5"))
        #expect(content.contains("scrollback-limit = 2000000"))
        #expect(content.contains("copy-on-select = false"))
        #expect(content.contains("clipboard-read = ask"))
    }
}

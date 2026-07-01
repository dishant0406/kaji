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
            content: "[colors]\nbackground = #000000\nforeground = #FFFFFF\ncursor = #FFFFFF"
        )

        let content = ThemeService.updatedConfigContent(
            from: "font_size = 16",
            themeIdentifier: preview.identifier,
            theme: preview,
            typographyLines: TermyTypographyDefaults.lines(fontSize: 18, fontFamily: "JetBrains Mono"),
            terminalLines: TermyTerminalConfigDefaults.lines()
        )

        #expect(content.contains("[colors]"))
        #expect(content.contains("background = #000000"))
        #expect(content.contains("font_size = 18"))
        #expect(content.contains("font_family = \"JetBrains Mono\""))
        #expect(content.contains("cursor_style = line"))
        #expect(content.contains("cursor_blink = false"))
        #expect(content.contains("shell_integration_enabled = true"))
        #expect(content.contains("mouse_scroll_multiplier = 3.0"))
        #expect(content.contains("scrollback_history = 2000000"))
        #expect(content.contains("copy_on_select = false"))
    }
}

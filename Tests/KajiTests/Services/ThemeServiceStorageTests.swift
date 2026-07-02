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
            typographyLines: TermyTypographyDefaults.lines(settings: .test(fontFamily: "JetBrains Mono", fontSize: 18)),
            terminalLines: TermyTerminalConfigDefaults.lines()
        )

        #expect(content.contains("[colors]"))
        #expect(content.contains("background = #000000"))
        #expect(content.contains("font_size = 18"))
        #expect(content.contains("font_family = \"JetBrains Mono\""))
        #expect(content.contains("line_height = 1.2"))
        #expect(content.contains("term = xterm-256color"))
        #expect(content.contains("colorterm = truecolor"))
        #expect(content.contains("cursor_style = line"))
        #expect(content.contains("cursor_blink = false"))
        #expect(content.contains("padding_x = 12"))
        #expect(content.contains("padding_y = 8"))
        #expect(content.contains("shell_integration_enabled = true"))
        #expect(content.contains("mouse_scroll_multiplier = 3.0"))
        #expect(content.contains("scrollback_history = 10000"))
        #expect(content.contains("inactive_tab_scrollback = 1000"))
        #expect(content.contains("copy_on_select = false"))
    }
}

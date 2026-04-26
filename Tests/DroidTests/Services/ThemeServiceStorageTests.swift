import Testing

@testable import Droid

struct ThemeServiceStorageTests {
    @Test
    func addsTerminalWritingDefaultsToGeneratedConfig() {
        let preview = ThemePreview(
            identifier: "noir",
            name: "Noir",
            source: .external,
            draft: ThemeDraft(name: "Noir", slug: "noir", colors: ThemeDraft.droidDefaults.colors),
            content: ""
        )

        let content = ThemeService.updatedConfigContent(
            from: "font-size = 16",
            themeIdentifier: preview.identifier,
            theme: preview
        )

        #expect(content.contains("theme = \"noir\""))
        #expect(content.contains("font-size = 16"))
        #expect(content.contains("font-family = \"SF Mono\""))
        #expect(content.contains("cursor-style = bar"))
        #expect(content.contains("cursor-style-blink = true"))
        #expect(content.contains("cursor-click-to-move = true"))
        #expect(content.contains("shell-integration = detect"))
    }
}

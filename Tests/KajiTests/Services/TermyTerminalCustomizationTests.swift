import Testing

@testable import Kaji

struct TermyTerminalCustomizationTests {
    @Test
    func typographyDefaultsUseTerminalSettings() {
        let lines = TermyTypographyDefaults.lines(settings: .test(fontFamily: "JetBrains Mono", fontSize: 15.5, lineHeight: 1.35))

        #expect(lines.contains("font_family = \"JetBrains Mono\""))
        #expect(lines.contains("ui_font_family = \"JetBrains Mono\""))
        #expect(lines.contains("font_size = 15.5"))
        #expect(lines.contains("line_height = 1.35"))
    }

    @Test
    func defaultTerminalFontUsesBundledPromptFont() {
        #expect(TerminalSettingsSnapshot.default.fontFamily == TerminalBundledFont.familyName)
        #expect(TermyRenderConfig.default.fontFamily == TerminalBundledFont.familyName)
    }

    @Test
    func bundledTerminalFontRegistersAndSupportsPromptGlyphs() {
        #expect(TerminalBundledFont.registerIfNeeded())
        #expect(TerminalBundledFont.isAvailable())
        #expect(TerminalBundledFont.supportsPromptGlyphs())
    }

    @Test
    func fontOptionsPreferBundledFontAndKeepCurrentSelection() {
        let options = TerminalFontOptions.options(
            current: "Custom Mono",
            installedFonts: ["Menlo", TerminalBundledFont.familyName, "Menlo"]
        )

        #expect(options == [TerminalBundledFont.familyName, "Menlo", "Custom Mono"])
    }

    @Test
    func terminalDefaultsWriteModernTermySettings() {
        let lines = TermyTerminalConfigDefaults.lines(settings: .test(paddingX: 14, paddingY: 6, cursorStyle: .block, cursorBlink: true))

        #expect(lines.contains("term = xterm-256color"))
        #expect(lines.contains("colorterm = truecolor"))
        #expect(lines.contains("cursor_style = block"))
        #expect(lines.contains("cursor_blink = true"))
        #expect(lines.contains("padding_x = 14"))
        #expect(lines.contains("padding_y = 6"))
    }

    @Test
    func configDiagnosticsReportInvalidValues() {
        let diagnostics = TermyConfigDiagnostics.load(contents: "font_size = nope")

        #expect(!diagnostics.isEmpty)
        #expect(diagnostics.contains { $0.kind == .invalidValue || $0.kind == .invalidSyntax })
    }
}

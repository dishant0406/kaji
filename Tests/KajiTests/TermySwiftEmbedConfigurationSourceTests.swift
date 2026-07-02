import Foundation
import Testing

@testable import TermySwiftEmbed

struct TermySwiftEmbedConfigurationSourceTests {
    @Test
    func loadsRenderConfigFromExplicitContents() throws {
        let config = try LibTermyTerminal.loadRenderConfig(configurationSource: .contents(Self.kajiConfig))

        #expect(config.foreground == TerminalRGBA(redByte: 255, greenByte: 255, blueByte: 255, alphaByte: 255))
        #expect(config.background == TerminalRGBA(redByte: 16, greenByte: 16, blueByte: 16, alphaByte: 255))
        #expect(config.cursor == TerminalRGBA(redByte: 255, greenByte: 199, blueByte: 153, alphaByte: 255))
        #expect(config.cursorStyle == .line)
        #expect(config.cursorBlink == false)
    }

    @Test
    func loadsRenderConfigFromExplicitPath() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.txt")
        try Self.kajiConfig.write(to: file, atomically: true, encoding: .utf8)

        let config = try LibTermyTerminal.loadRenderConfig(configurationSource: .path(file.path))

        #expect(config.background == TerminalRGBA(redByte: 16, greenByte: 16, blueByte: 16, alphaByte: 255))
        #expect(config.cursorStyle == .line)
    }

    @Test
    func loadsRuntimeScrollbackFromExplicitContents() throws {
        let config = try TermyRuntimeConfigurationLoader.load(source: .contents("""
        scrollback_history = 777
        inactive_tab_scrollback = 123
        """))

        #expect(config.scrollbackHistory == 777)
        #expect(config.inactiveTabScrollback == 123)
    }

    @Test
    func clampsOversizedRuntimeScrollbackFromStaleContents() throws {
        let config = try TermyRuntimeConfigurationLoader.load(source: .contents("""
        scrollback_history = 2000000
        inactive_tab_scrollback = 500000
        """))

        #expect(config.scrollbackHistory == 100_000)
        #expect(config.inactiveTabScrollback == 10_000)
    }

    @Test
    func clampsInactiveScrollbackToActiveLimit() throws {
        let config = try TermyRuntimeConfigurationLoader.load(source: .contents("""
        scrollback_history = 2000
        inactive_tab_scrollback = 5000
        """))

        #expect(config.scrollbackHistory == 2_000)
        #expect(config.inactiveTabScrollback == 2_000)
    }

    private static let kajiConfig = """
    [colors]
    black = #242424
    red = #E07070
    green = #73C990
    yellow = #FFC799
    blue = #688DFF
    magenta = #CF68FF
    cyan = #3FDEBE
    white = #BBBBBB
    bright_black = #555555
    bright_red = #FF8080
    bright_green = #A8FF78
    bright_yellow = #FFD9B3
    bright_blue = #9BB2F0
    bright_magenta = #E8A1FF
    bright_cyan = #7FFFD4
    bright_white = #FFFFFF
    background = #101010
    foreground = #FFFFFF
    cursor = #FFC799
    cursor_style = line
    cursor_blink = false
    """
}

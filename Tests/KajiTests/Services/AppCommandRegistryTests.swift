import Testing

@testable import Kaji

@Suite("AppCommandRegistry")
struct AppCommandRegistryTests {
    @Test("commands mirror shortcut definitions")
    func commandsMirrorShortcutDefinitions() {
        #expect(AppCommandRegistry.commands.map(\.id) == ShortcutReferenceCatalog.definitions.map(\.action))
        #expect(AppCommandRegistry.commands.count == ShortcutAction.allCases.count)
    }

    @Test("editor commands expose editor actions")
    func editorCommands() {
        let actions = Set(AppCommandRegistry.editorCommands.map(\.id))

        #expect(actions.contains(.findInTerminal))
        #expect(actions.contains(.replaceInEditor))
        #expect(actions.contains(.saveFile))
        #expect(actions.contains(.goToSymbol))
        #expect(actions.contains(.goToLine))
        #expect(actions.contains(.inlineEdit))
    }

    @Test("search ranks exact and prefix matches")
    func search() {
        let results = AppCommandRegistry.search("go to")

        #expect(results.prefix(2).map(\.id).contains(.goToLine))
        #expect(results.prefix(2).map(\.id).contains(.goToSymbol))
    }

    @Test("command palette command is searchable")
    func commandPaletteCommand() {
        let results = AppCommandRegistry.search("command palette")

        #expect(results.first?.id == .commandPalette)
    }
}

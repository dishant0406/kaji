import Testing

@testable import Kaji

struct ShortcutReferenceCatalogTests {
    @Test
    func keyboardReferenceIncludesEveryShortcutAction() {
        #expect(Set(ShortcutReferenceCatalog.keyboardActions) == Set(ShortcutAction.allCases))
        #expect(ShortcutReferenceCatalog.keyboardActions.count == ShortcutAction.allCases.count)
    }

    @Test
    func commandKReferenceIncludesAskRoutingTokens() {
        let tokens = Set(ShortcutReferenceCatalog.commandKReferences.map(\.token))

        #expect(tokens.contains(":h:"))
        #expect(tokens.contains(":t:"))
        #expect(tokens.contains(":pa:"))
        #expect(tokens.contains("/session"))
        #expect(tokens.contains("/bookmark"))
        #expect(tokens.contains("/lid"))
    }

    @Test
    func localReferenceIncludesContextualShortcuts() {
        let shortcuts = ShortcutReferenceCatalog.localShortcuts

        #expect(shortcuts.contains { $0.keys == "Cmd+D" && $0.name == "Select next occurrence" })
        #expect(shortcuts.contains { $0.keys == "Cmd+Tab" && $0.name == "Attach from clipboard" })
        #expect(shortcuts.contains { $0.keys == "Delete" && $0.category == "File Tree" })
    }
}

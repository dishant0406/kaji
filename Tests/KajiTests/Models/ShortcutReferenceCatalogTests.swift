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
    }
}

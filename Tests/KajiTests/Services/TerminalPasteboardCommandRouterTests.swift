import Testing

@testable import Kaji

@MainActor
struct TerminalPasteboardCommandRouterTests {
    @Test
    func pasteSendsPasteboardTextToFocusedTerminal() {
        let target = PasteboardTarget()
        let router = TerminalPasteboardCommandRouter(
            targetProvider: { target },
            pasteboardTextProvider: { "hello" }
        )

        #expect(router.paste())
        #expect(target.focusCount == 1)
        #expect(target.pastedText == ["hello"])
    }

    @Test
    func pastePrefersFirstResponderTerminalOverFocusedFallback() {
        let firstResponderTarget = PasteboardTarget()
        let focusedTarget = PasteboardTarget()
        let router = TerminalPasteboardCommandRouter(
            firstResponderTargetProvider: { firstResponderTarget },
            targetProvider: { focusedTarget },
            pasteboardTextProvider: { "hello" }
        )

        #expect(router.paste())
        #expect(firstResponderTarget.focusCount == 1)
        #expect(firstResponderTarget.pastedText == ["hello"])
        #expect(focusedTarget.focusCount == 0)
        #expect(focusedTarget.pastedText.isEmpty)
    }

    @Test
    func pasteFallsBackWhenFirstResponderTerminalCannotReceiveCommands() {
        let firstResponderTarget = PasteboardTarget()
        let focusedTarget = PasteboardTarget()
        firstResponderTarget.canReceiveTerminalPasteboardCommand = false
        let router = TerminalPasteboardCommandRouter(
            firstResponderTargetProvider: { firstResponderTarget },
            targetProvider: { focusedTarget },
            pasteboardTextProvider: { "hello" }
        )

        #expect(router.paste())
        #expect(firstResponderTarget.pastedText.isEmpty)
        #expect(focusedTarget.pastedText == ["hello"])
    }

    @Test
    func pasteReturnsFalseWhenPasteboardIsEmpty() {
        let target = PasteboardTarget()
        let router = TerminalPasteboardCommandRouter(
            targetProvider: { target },
            pasteboardTextProvider: { "" }
        )

        #expect(!router.paste())
        #expect(target.focusCount == 0)
        #expect(target.pastedText.isEmpty)
    }

    @Test
    func pasteDefersToResponderWhenTextInputOwnsFocus() {
        let target = PasteboardTarget()
        let router = TerminalPasteboardCommandRouter(
            targetProvider: { target },
            pasteboardTextProvider: { "hello" },
            shouldDeferToResponder: { true }
        )

        #expect(!router.paste())
        #expect(target.focusCount == 0)
        #expect(target.pastedText.isEmpty)
    }

    @Test
    func copyUsesFocusedTerminalSelection() {
        let target = PasteboardTarget()
        let router = TerminalPasteboardCommandRouter(
            targetProvider: { target },
            pasteboardTextProvider: { nil }
        )

        #expect(router.copy())
        #expect(target.copyCount == 1)
    }

    @Test
    func copyFallsBackWhenTerminalCannotReceiveCommands() {
        let target = PasteboardTarget()
        target.canReceiveTerminalPasteboardCommand = false
        let router = TerminalPasteboardCommandRouter(
            targetProvider: { target },
            pasteboardTextProvider: { nil }
        )

        #expect(!router.copy())
        #expect(target.copyCount == 0)
    }
}

@MainActor
private final class PasteboardTarget: TerminalPasteboardCommandTarget {
    var canReceiveTerminalPasteboardCommand = true
    var copyCount = 0
    var focusCount = 0
    var pastedText: [String] = []

    func copyTerminalSelection() -> Bool {
        copyCount += 1
        return true
    }

    func pasteTextIntoTerminal(_ text: String) -> Bool {
        pastedText.append(text)
        return true
    }

    func focusTerminalInput() {
        focusCount += 1
    }
}

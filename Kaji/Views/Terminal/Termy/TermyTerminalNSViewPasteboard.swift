import AppKit

extension TermyTerminalNSView: TerminalPasteboardCommandTarget {
    var canReceiveTerminalPasteboardCommand: Bool {
        hasLiveSurface && surfaceVisible && !overlayActive && !searchVisible
    }

    func copyTerminalSelection() -> Bool {
        terminal?.copySelection() ?? false
    }

    func pasteTextIntoTerminal(_ text: String) -> Bool {
        guard canReceiveTerminalPasteboardCommand,
              !text.isEmpty,
              let terminal
        else {
            return false
        }
        if surfaceVisible {
            terminal.resume()
        }
        terminal.paste(text)
        return true
    }

    func focusTerminalInput() {
        focusKeyboardCapture()
    }
}

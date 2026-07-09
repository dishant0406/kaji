import Foundation

extension TermyTerminalNSView {
    func foregroundProcessGroupID() -> Int32? {
        terminal?.foregroundProcessGroupID()
    }

    func terminalProcessRootID() -> Int32? {
        terminal?.childProcessID()
    }

    func ttyName() -> String? {
        nil
    }

    func visibleText() -> String? {
        terminal?.visibleText()
    }

    func needsConfirmQuit() -> Bool {
        terminal?.needsConfirmQuit() ?? false
    }
}

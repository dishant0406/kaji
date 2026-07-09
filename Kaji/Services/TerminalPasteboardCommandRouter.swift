import AppKit

@MainActor
protocol TerminalPasteboardCommandTarget: AnyObject {
    var canReceiveTerminalPasteboardCommand: Bool { get }
    func copyTerminalSelection() -> Bool
    func pasteTextIntoTerminal(_ text: String) -> Bool
    func focusTerminalInput()
}

@MainActor
struct TerminalPasteboardCommandRouter {
    private let firstResponderTargetProvider: () -> TerminalPasteboardCommandTarget?
    private let targetProvider: () -> TerminalPasteboardCommandTarget?
    private let pasteboardTextProvider: () -> String?
    private let shouldDeferToResponder: () -> Bool

    init(
        firstResponderTargetProvider: @escaping () -> TerminalPasteboardCommandTarget? = { nil },
        targetProvider: @escaping () -> TerminalPasteboardCommandTarget?,
        pasteboardTextProvider: @escaping () -> String?,
        shouldDeferToResponder: @escaping () -> Bool = { false }
    ) {
        self.firstResponderTargetProvider = firstResponderTargetProvider
        self.targetProvider = targetProvider
        self.pasteboardTextProvider = pasteboardTextProvider
        self.shouldDeferToResponder = shouldDeferToResponder
    }

    func copy() -> Bool {
        guard !shouldDeferToResponder(),
              let target = commandTarget()
        else {
            return false
        }
        return target.copyTerminalSelection()
    }

    func paste() -> Bool {
        guard !shouldDeferToResponder(),
              let text = pasteboardTextProvider(),
              !text.isEmpty,
              let target = commandTarget()
        else {
            return false
        }
        target.focusTerminalInput()
        return target.pasteTextIntoTerminal(text)
    }

    private func commandTarget() -> TerminalPasteboardCommandTarget? {
        if let target = firstResponderTargetProvider(), target.canReceiveTerminalPasteboardCommand {
            return target
        }
        guard let target = targetProvider(), target.canReceiveTerminalPasteboardCommand else {
            return nil
        }
        return target
    }
}

extension TerminalPasteboardCommandRouter {
    static func focusedTerminal(
        appState: AppState,
        registry: TerminalViewRegistry = .shared
    ) -> TerminalPasteboardCommandRouter {
        TerminalPasteboardCommandRouter(
            firstResponderTargetProvider: {
                registry.viewOwningFirstResponder(NSApp.keyWindow?.firstResponder)
            },
            targetProvider: {
                guard let projectID = appState.activeProjectID,
                      let pane = appState.focusedArea(for: projectID)?.activeTab?.content.pane
                else {
                    return nil
                }
                return registry.existingView(for: pane.id)
            },
            pasteboardTextProvider: {
                NSPasteboard.general.string(forType: .string)
            },
            shouldDeferToResponder: {
                TerminalPasteboardResponderPolicy.shouldDefer(NSApp.keyWindow?.firstResponder)
            }
        )
    }
}

enum TerminalPasteboardResponderPolicy {
    static func shouldDefer(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if responder is NSText {
            return true
        }
        if responder is NSTextView {
            return true
        }
        if responder is NSTextField {
            return true
        }
        return false
    }
}

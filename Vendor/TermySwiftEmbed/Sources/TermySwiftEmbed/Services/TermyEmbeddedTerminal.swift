import Foundation

@MainActor
public final class TermyEmbeddedTerminal: ObservableObject {
    let terminal: TerminalViewModel

    public init(
        workingDirectory: String,
        command: String?,
        envVars: [(key: String, value: String)],
        configurationSource: TermyConfigurationSource = .defaultConfig
    ) {
        terminal = TerminalViewModel(
            workingDirectory: workingDirectory,
            startupCommand: command,
            envVars: envVars,
            configurationSource: configurationSource
        )
    }

    public var isExited: Bool { terminal.isExited }
    public var title: String { terminal.title }
    public var searchMatchCount: Int { terminal.searchMatches.count }
    public var activeSearchIndex: Int? { terminal.searchMatches.isEmpty ? nil : terminal.activeSearchMatchIndex + 1 }

    public func start() {
        terminal.start()
    }

    public func stop() {
        terminal.stop()
    }

    public func setFocused(_ focused: Bool) {
        terminal.setPaneFocused(focused)
    }

    public func suspend() {
        terminal.suspendRefresh()
    }

    public func resume() {
        terminal.resumeRefresh()
    }

    public func reloadConfiguration() {
        terminal.reloadConfiguration()
    }

    public func sendText(_ text: String) {
        terminal.send(bytes: Array(text.utf8))
    }

    public func sendReturnKey() {
        terminal.sendKey(TerminalKeyInput(
            key: "enter",
            keyChar: nil,
            control: false,
            alt: false,
            shift: false,
            platform: false,
            function: false,
            eventKind: .press
        ))
    }

    public func sendEscapeKey() {
        terminal.sendKey(TerminalKeyInput(
            key: "escape",
            keyChar: nil,
            control: false,
            alt: false,
            shift: false,
            platform: false,
            function: false,
            eventKind: .press
        ))
    }

    public func paste(_ text: String) {
        terminal.paste(text)
    }

    public func copySelection() -> Bool {
        terminal.copySelection()
    }

    public func updateSearch(_ query: String) {
        terminal.updateSearch(query)
    }

    public func clearSearch() {
        terminal.updateSearch("")
    }

    public func selectNextSearchMatch() {
        terminal.selectNextSearchMatch()
    }

    public func selectPreviousSearchMatch() {
        terminal.selectPreviousSearchMatch()
    }

    public func visibleText() -> String {
        terminal.visibleTextSnapshot()
    }

    public func needsConfirmQuit() -> Bool {
        !terminal.isExited
    }

    public func foregroundProcessGroupID() -> Int32? {
        terminal.childProcessID()
    }
}

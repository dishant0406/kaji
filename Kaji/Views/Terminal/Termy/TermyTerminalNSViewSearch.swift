import AppKit

extension TermyTerminalNSView {
    func sendText(_ text: String) {
        terminal?.sendText(text)
    }

    func sendReturnKey() {
        terminal?.sendReturnKey()
    }

    func sendEscapeKey() {
        terminal?.sendEscapeKey()
    }

    func startSearch() {
        searchVisible = true
        onSearchStart?(nil)
        syncHostedView()
    }

    func sendSearchQuery(_ needle: String) {
        terminal?.updateSearch(needle)
        publishSearchState()
    }

    func navigateSearch(direction: SearchDirection) {
        switch direction {
        case .next:
            terminal?.selectNextSearchMatch()
        case .previous:
            terminal?.selectPreviousSearchMatch()
        }
        publishSearchState()
    }

    func endSearch() {
        searchVisible = false
        terminal?.clearSearch()
        onSearchEnd?()
        syncHostedView()
    }

    func publishSearchState() {
        guard let terminal else { return }
        onSearchTotal?(terminal.searchMatchCount)
        onSearchSelected?(terminal.activeSearchIndex)
    }
}

import Foundation
import Testing

@testable import Kaji

@Suite("BrowserPaneActivationPolicy")
struct BrowserPaneActivationPolicyTests {
    @Test("selected page is active only when pane is visible")
    func selectedPageRequiresVisiblePane() {
        let selected = UUID()

        #expect(BrowserPaneActivationPolicy.pageIsActive(
            pageID: selected,
            selectedPageID: selected,
            paneIsVisible: true
        ))
        #expect(!BrowserPaneActivationPolicy.pageIsActive(
            pageID: selected,
            selectedPageID: selected,
            paneIsVisible: false
        ))
    }

    @Test("non selected page is inactive")
    func nonSelectedPageIsInactive() {
        #expect(!BrowserPaneActivationPolicy.pageIsActive(
            pageID: UUID(),
            selectedPageID: UUID(),
            paneIsVisible: true
        ))
    }

    @Test("browser startup preserves hidden state when pane hides mid startup")
    func startupPreservesHiddenState() {
        #expect(BrowserPaneActivationPolicy.browserActiveStateAfterStartup(requestedActiveState: nil))
        #expect(BrowserPaneActivationPolicy.browserActiveStateAfterStartup(requestedActiveState: true))
        #expect(!BrowserPaneActivationPolicy.browserActiveStateAfterStartup(requestedActiveState: false))
    }
}

import Foundation
import Testing

@testable import Kaji

@Suite("BrowserControllerRetentionPolicy")
struct BrowserControllerRetentionPolicyTests {
    @Test("retains only selected page controller")
    func retainsOnlySelectedPageController() {
        let first = UUID()
        let second = UUID()

        #expect(BrowserControllerRetentionPolicy.retainedControllerIDs(
            pageIDs: [first, second],
            selectedPageID: second
        ) == [second])
    }

    @Test("falls back to first page when selection is stale")
    func fallsBackToFirstPageWhenSelectionIsStale() {
        let first = UUID()

        #expect(BrowserControllerRetentionPolicy.retainedControllerIDs(
            pageIDs: [first],
            selectedPageID: UUID()
        ) == [first])
    }
}

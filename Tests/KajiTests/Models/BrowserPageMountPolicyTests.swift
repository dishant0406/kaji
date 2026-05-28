import Foundation
import Testing

@testable import Kaji

@Suite("BrowserPageMountPolicy")
struct BrowserPageMountPolicyTests {
    @Test("mounts only the selected browser page")
    func selectedPageOnly() {
        let pages = [UUID(), UUID(), UUID()]

        #expect(BrowserPageMountPolicy.mountedPageIDs(
            pageIDs: pages,
            selectedPageID: pages[1]
        ) == [pages[1]])
    }

    @Test("falls back to the first page when selected page is missing")
    func firstPageFallback() {
        let pages = [UUID(), UUID()]

        #expect(BrowserPageMountPolicy.mountedPageIDs(
            pageIDs: pages,
            selectedPageID: UUID()
        ) == [pages[0]])
    }

    @Test("returns empty mount set for empty browser state")
    func emptyPages() {
        #expect(BrowserPageMountPolicy.mountedPageIDs(pageIDs: [], selectedPageID: UUID()).isEmpty)
    }
}

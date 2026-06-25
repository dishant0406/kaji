import Foundation
import Testing

@testable import Kaji

@Suite("BrowserSession", .serialized)
@MainActor
struct BrowserSessionTests {
    @Test("session preserves one controller registry for its lifetime")
    func sessionPreservesControllerRegistry() {
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let session = BrowserSession(key: key, state: BrowserPaneState(projectPath: "/tmp/test"))
        let pageID = session.state.selectedPageID

        let first = session.controllers.controller(for: pageID)
        let second = session.controllers.controller(for: pageID)

        #expect(first === second)
        #expect(session.key == key)
        #expect(session.state.projectPath == "/tmp/test")
    }

    @Test("touch refreshes session usage timestamp")
    func touchRefreshesTimestamp() async throws {
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let session = BrowserSession(key: key, state: BrowserPaneState(projectPath: "/tmp/test"))
        let original = session.lastUsedAt

        try await Task.sleep(nanoseconds: 1_000_000)
        session.touch()

        #expect(session.lastUsedAt > original)
    }

    @Test("page summary is capped")
    func pageSummaryIsCapped() {
        let page = BrowserPageState(pageSummary: String(repeating: "a", count: 130_000))

        #expect(page.pageSummary.count == 120_000)

        page.pageSummary = String(repeating: "b", count: 130_000)

        #expect(page.pageSummary.count == 120_000)
    }
}

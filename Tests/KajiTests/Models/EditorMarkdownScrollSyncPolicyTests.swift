import Testing

@testable import Kaji

@Suite("EditorMarkdownScrollSyncPolicy")
struct EditorMarkdownScrollSyncPolicyTests {
    @Test("applies stable scheduled sync")
    func appliesStableScheduledSync() {
        #expect(EditorMarkdownScrollSyncPolicy.shouldApplyScheduledSync(
            sourceScrollY: 120,
            currentScrollY: 120.25
        ))
    }

    @Test("skips stale scheduled sync after scroll moves")
    func skipsStaleScheduledSyncAfterScrollMoves() {
        #expect(!EditorMarkdownScrollSyncPolicy.shouldApplyScheduledSync(
            sourceScrollY: 120,
            currentScrollY: 121
        ))
    }
}

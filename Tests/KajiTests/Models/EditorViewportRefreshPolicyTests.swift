import Testing

@testable import Kaji

@Suite("EditorViewportRefreshPolicy")
struct EditorViewportRefreshPolicyTests {
    @Test("starts one scroll refresh task at a time")
    func startsOneTaskAtATime() {
        #expect(EditorViewportRefreshPolicy.shouldCreateScrollRefreshTask(hasPendingTask: false))
        #expect(!EditorViewportRefreshPolicy.shouldCreateScrollRefreshTask(hasPendingTask: true))
    }

    @Test("skips scroll refresh while viewport edit is applying")
    func skipsWhileEditingViewport() {
        #expect(EditorViewportRefreshPolicy.shouldRunScrollRefresh(isEditingViewport: false))
        #expect(!EditorViewportRefreshPolicy.shouldRunScrollRefresh(isEditingViewport: true))
    }
}

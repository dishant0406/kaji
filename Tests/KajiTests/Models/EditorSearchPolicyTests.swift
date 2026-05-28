import Testing

@testable import Kaji

@Suite("EditorSearchPolicy")
struct EditorSearchPolicyTests {
    @Test("maximum tracked matches is bounded")
    func maximumTrackedMatchesIsBounded() {
        #expect(EditorSearchPolicy.maximumTrackedMatches > 0)
        #expect(EditorSearchPolicy.maximumTrackedMatches <= 20000)
    }
}

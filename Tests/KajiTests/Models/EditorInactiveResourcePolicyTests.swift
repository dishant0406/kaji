import Testing

@testable import Kaji

@Suite("EditorInactiveResourcePolicy")
@MainActor
struct EditorInactiveResourcePolicyTests {
    @Test("releases active loads")
    func releasesActiveLoads() {
        #expect(EditorInactiveResourcePolicy.shouldReleaseBackingStore(
            isModified: false,
            isLoading: true,
            isIncrementalLoading: false,
            backingStore: nil
        ))
    }

    @Test("keeps modified documents")
    func keepsModifiedDocuments() {
        let store = TextBackingStore()
        store.loadFromText(String(repeating: "x", count: 1_100_000))

        #expect(!EditorInactiveResourcePolicy.shouldReleaseBackingStore(
            isModified: true,
            isLoading: false,
            isIncrementalLoading: false,
            backingStore: store
        ))
    }
}

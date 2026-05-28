import Testing

@testable import Kaji

@Suite("Editor fold region state")
@MainActor
struct EditorFoldRegionStateTests {
    @Test("empty collapsed fold set returns no collapsed regions")
    func emptyCollapsedFoldSetReturnsNoCollapsedRegions() {
        let state = EditorTabState(projectPath: "/tmp", filePath: "/tmp/file.rb")
        let store = TextBackingStore()
        store.loadFromText("""
        # region one
        puts 1
        # endregion
        """)
        state.backingStore = store

        #expect(state.collapsedFoldRegions().isEmpty)
    }
}

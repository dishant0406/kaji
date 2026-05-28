import Testing

@testable import Kaji

@Suite("EditorCollapsedFoldPolicy")
struct EditorCollapsedFoldPolicyTests {
    @Test("skips fold region resolution when no regions are collapsed")
    func skipsResolutionWhenNoRegionsAreCollapsed() {
        #expect(!EditorCollapsedFoldPolicy.shouldResolveFoldRegions(collapsedIDs: []))
        #expect(EditorCollapsedFoldPolicy.collapsedRegions([EditorFoldRegion(startLine: 0, endLine: 2)], collapsedIDs: []).isEmpty)
    }

    @Test("filters collapsed regions by id")
    func filtersCollapsedRegionsByID() {
        let first = EditorFoldRegion(startLine: 0, endLine: 2)
        let second = EditorFoldRegion(startLine: 4, endLine: 8)

        #expect(EditorCollapsedFoldPolicy.collapsedRegions([first, second], collapsedIDs: [second.id]) == [second])
    }
}

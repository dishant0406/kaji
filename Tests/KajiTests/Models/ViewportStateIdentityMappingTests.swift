import Testing

@testable import Kaji

@Suite("ViewportState identity mapping")
@MainActor
struct ViewportStateIdentityMappingTests {
    @Test("unfolded viewports stay sparse")
    func unfoldedViewportsStaySparse() {
        let store = TextBackingStore()
        store.loadFromText((0 ..< 1000).map { "line \($0)" }.joined(separator: "\n"))
        let viewport = ViewportState(backingStore: store)

        #expect(viewport.visualLines.isEmpty)
        #expect(viewport.visualLineCount == 1000)

        viewport.applyViewport(10 ..< 13)

        #expect(viewport.viewportText() == "line 10\nline 11\nline 12")
        #expect(viewport.backingStoreLine(forViewportLine: 2) == 12)
        #expect(viewport.viewportLine(forBackingStoreLine: 11) == 1)
    }
}

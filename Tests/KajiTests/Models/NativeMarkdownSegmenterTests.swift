import Testing

@testable import Kaji

@Suite("Native markdown segmentation")
struct NativeMarkdownSegmenterTests {
    @Test("extracts named begin end blocks as separate segments")
    func extractsNamedBeginEndBlocks() {
        let content = """
        Before

        <!-- BEGIN COMPOUND PI TOOL MAP -->
        # Compound Engineering
        Install with: pi install npm:pi-subagents
        <!-- END COMPOUND PI TOOL MAP -->

        After
        """

        let segments = NativeMarkdownSegmenter.segments(from: content)

        #expect(segments.map(\.kind) == [.markdown, .managedBlock(title: "COMPOUND PI TOOL MAP"), .markdown])
        #expect(segments[0].content == "Before")
        #expect(segments[1].content.contains("Compound Engineering"))
        #expect(!segments[1].content.contains("BEGIN COMPOUND"))
        #expect(segments[2].content == "After")
    }

    @Test("supports arbitrary matching marker names")
    func supportsArbitraryMarkerNames() {
        let content = """
        <!-- BEGIN GENERATED TOOL OUTPUT -->
        ## Tool output
        <!-- END GENERATED TOOL OUTPUT -->
        """

        let segments = NativeMarkdownSegmenter.segments(from: content)

        #expect(segments.map(\.kind) == [.managedBlock(title: "GENERATED TOOL OUTPUT")])
        #expect(segments[0].content == "## Tool output")
    }

    @Test("ignores mismatched end markers")
    func ignoresMismatchedEndMarkers() {
        let content = """
        <!-- BEGIN FIRST BLOCK -->
        keep visible
        <!-- END SECOND BLOCK -->
        """

        let segments = NativeMarkdownSegmenter.segments(from: content)

        #expect(segments.count == 1)
        #expect(segments[0].kind == .markdown)
        #expect(segments[0].content.contains("BEGIN FIRST BLOCK"))
    }

    @Test("keeps incomplete marker blocks as markdown")
    func keepsIncompleteBlockAsMarkdown() {
        let content = """
        <!-- BEGIN COMPOUND PI TOOL MAP -->
        # Missing end
        """

        let segments = NativeMarkdownSegmenter.segments(from: content)

        #expect(segments.count == 1)
        #expect(segments[0].kind == .markdown)
        #expect(segments[0].content.contains("BEGIN COMPOUND"))
    }
}

import Testing

@testable import Kaji

@Suite("Split diff inline pairing")
struct SplitDiffPairingInlineTests {
    @Test("paired rows preserve inline segment metadata")
    func pairedRowsPreserveInlineSegments() {
        let oldSegments = [DiffInlineSegment(text: "old", emphasized: true)]
        let newSegments = [DiffInlineSegment(text: "new", emphasized: true)]
        let rows = [
            DiffDisplayRow(kind: .hunk, oldLineNumber: nil, newLineNumber: nil, oldText: nil, newText: nil, text: "@@ -1 +1 @@"),
            DiffDisplayRow(
                kind: .deletion,
                oldLineNumber: 1,
                newLineNumber: nil,
                oldText: "old",
                newText: nil,
                text: "-old",
                oldInlineSegments: oldSegments
            ),
            DiffDisplayRow(
                kind: .addition,
                oldLineNumber: nil,
                newLineNumber: 1,
                oldText: nil,
                newText: "new",
                text: "+new",
                newInlineSegments: newSegments
            ),
        ]

        let paired = SplitDiffPairedRow.pair(rows)
        let content = paired.first { $0.left?.kind == .deletion && $0.right?.kind == .addition }

        #expect(content?.left?.oldInlineSegments == oldSegments)
        #expect(content?.right?.newInlineSegments == newSegments)
    }
}

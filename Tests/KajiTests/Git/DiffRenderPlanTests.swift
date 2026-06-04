import Testing

@testable import Kaji

@Suite("Diff render plan")
struct DiffRenderPlanTests {
    @Test("precomputes unified and split chunks")
    func precomputesChunks() {
        let rows = [
            DiffDisplayRow(kind: .hunk, oldLineNumber: nil, newLineNumber: nil, oldText: nil, newText: nil, text: "@@ -1 +1 @@"),
            DiffDisplayRow(kind: .deletion, oldLineNumber: 1, newLineNumber: nil, oldText: "let color = \"red\"", newText: nil, text: "-let color = \"red\""),
            DiffDisplayRow(kind: .addition, oldLineNumber: nil, newLineNumber: 1, oldText: nil, newText: "let color = \"blue\"", text: "+let color = \"blue\""),
            DiffDisplayRow(kind: .collapsed, oldLineNumber: nil, newLineNumber: nil, oldText: nil, newText: nil, text: "20 unmodified lines"),
            DiffDisplayRow(kind: .hunk, oldLineNumber: nil, newLineNumber: nil, oldText: nil, newText: nil, text: "@@ -10 +10 @@"),
            DiffDisplayRow(kind: .context, oldLineNumber: 10, newLineNumber: 10, oldText: "tail", newText: "tail", text: " tail"),
        ]

        let plan = DiffRenderPlan(rows: rows)

        #expect(plan.maxLineNumber == 10)
        #expect(plan.unifiedChunks.count == 3)
        #expect(plan.splitChunks.count == 3)
        #expect(plan.oldLineRowIndexes[1] == [1])
        #expect(plan.newLineRowIndexes[1] == [2])
        #expect(plan.changedRowIndexes == [1, 2])
    }

    @Test("split plan preserves inline segments")
    func splitPlanPreservesInlineSegments() {
        let oldSegments = [DiffInlineSegment(text: "red", emphasized: true)]
        let newSegments = [DiffInlineSegment(text: "blue", emphasized: true)]
        let rows = [
            DiffDisplayRow(kind: .hunk, oldLineNumber: nil, newLineNumber: nil, oldText: nil, newText: nil, text: "@@ -1 +1 @@"),
            DiffDisplayRow(
                kind: .deletion,
                oldLineNumber: 1,
                newLineNumber: nil,
                oldText: "red",
                newText: nil,
                text: "-red",
                oldInlineSegments: oldSegments
            ),
            DiffDisplayRow(
                kind: .addition,
                oldLineNumber: nil,
                newLineNumber: 1,
                oldText: nil,
                newText: "blue",
                text: "+blue",
                newInlineSegments: newSegments
            ),
        ]

        let plan = DiffRenderPlan(rows: rows)
        guard case let .codeBlock(block)? = plan.splitChunks.first else {
            Issue.record("Expected first split chunk to be a code block")
            return
        }

        #expect(block.leftRows[1].oldInlineSegments == oldSegments)
        #expect(block.rightRows[1].newInlineSegments == newSegments)
    }
}

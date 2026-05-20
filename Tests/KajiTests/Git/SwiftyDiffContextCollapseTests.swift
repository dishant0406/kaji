import Testing

@testable import Kaji

@Suite("SwiftyDiffAdapter context collapse")
struct SwiftyDiffContextCollapseTests {
    @Test("collapseContextRows preserves short runs")
    func collapseShortRun() {
        var rows: [DiffDisplayRow] = []
        for i in 0 ..< 12 {
            rows.append(DiffDisplayRow(
                kind: .context,
                oldLineNumber: i,
                newLineNumber: i,
                oldText: "line \(i)",
                newText: "line \(i)",
                text: " line \(i)"
            ))
        }
        let collapsed = SwiftyDiffAdapter.collapseContextRows(rows)
        #expect(collapsed.count == 12)
        #expect(collapsed.allSatisfy { $0.kind == .context })
    }

    @Test("collapseContextRows collapses long runs")
    func collapseLongRun() {
        var rows: [DiffDisplayRow] = []
        for i in 0 ..< 20 {
            rows.append(DiffDisplayRow(
                kind: .context,
                oldLineNumber: i,
                newLineNumber: i,
                oldText: "line \(i)",
                newText: "line \(i)",
                text: " line \(i)"
            ))
        }
        let collapsed = SwiftyDiffAdapter.collapseContextRows(rows)

        #expect(collapsed.count == 7)
        #expect(collapsed[0].kind == .context)
        #expect(collapsed[1].kind == .context)
        #expect(collapsed[2].kind == .context)
        #expect(collapsed[3].kind == .collapsed)
        #expect(collapsed[3].text == "14 unmodified lines")
        #expect(collapsed[4].kind == .context)
        #expect(collapsed[5].kind == .context)
        #expect(collapsed[6].kind == .context)
    }

    @Test("collapseContextRows preserves non-context rows")
    func collapsePreservesNonContext() {
        let rows: [DiffDisplayRow] = [
            DiffDisplayRow(kind: .hunk, oldLineNumber: nil, newLineNumber: nil, oldText: nil, newText: nil, text: "@@ -1,1 +1,1 @@"),
            DiffDisplayRow(kind: .deletion, oldLineNumber: 1, newLineNumber: nil, oldText: "old", newText: nil, text: "-old"),
            DiffDisplayRow(kind: .addition, oldLineNumber: nil, newLineNumber: 1, oldText: nil, newText: "new", text: "+new"),
        ]
        let collapsed = SwiftyDiffAdapter.collapseContextRows(rows)
        #expect(collapsed.count == 3)
    }

    @Test("collapseContextRows handles mixed context and changes")
    func collapseMixedContent() {
        var rows: [DiffDisplayRow] = []
        for i in 0 ..< 20 {
            rows.append(DiffDisplayRow(kind: .context, oldLineNumber: i, newLineNumber: i, oldText: "\(i)", newText: "\(i)", text: " \(i)"))
        }
        rows.append(DiffDisplayRow(kind: .deletion, oldLineNumber: 20, newLineNumber: nil, oldText: "x", newText: nil, text: "-x"))
        for i in 20 ..< 40 {
            rows.append(DiffDisplayRow(kind: .context, oldLineNumber: i, newLineNumber: i, oldText: "\(i)", newText: "\(i)", text: " \(i)"))
        }

        let collapsed = SwiftyDiffAdapter.collapseContextRows(rows)
        let collapsedMarkers = collapsed.filter { $0.kind == .collapsed }
        #expect(collapsedMarkers.count == 2)
    }
}

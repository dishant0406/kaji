import XCTest
@testable import TermySwiftEmbed

final class TermySwiftEmbedTerminalSelectionScrollbackTests: XCTestCase {
    func testSelectionProjectsOnlyVisibleBufferRows() {
        let selection = TerminalSelection(
            anchor: TerminalBufferPosition(col: 2, row: 3),
            active: TerminalBufferPosition(col: 4, row: 5)
        )

        let ranges = selection.rowRanges(cols: 10, rows: 3, visibleTop: 4)

        XCTAssertEqual(ranges, [
            TerminalSelectionRowRange(row: 0, startCol: 0, endCol: 9),
            TerminalSelectionRowRange(row: 1, startCol: 0, endCol: 4),
        ])
    }

    func testSelectionOutsideVisibleRowsDoesNotDraw() {
        let selection = TerminalSelection(
            anchor: TerminalBufferPosition(col: 0, row: 1),
            active: TerminalBufferPosition(col: 9, row: 2)
        )

        XCTAssertEqual(selection.rowRanges(cols: 10, rows: 3, visibleTop: 4), [])
    }

    func testFrameSelectedTextUsesScrolledBufferRows() {
        var frame = TerminalFrame.plainTextPreview("four\nfive\nsix", cols: 6, rows: 3)
        frame.historySize = 6
        frame.displayOffset = 2

        let selection = TerminalSelection(
            anchor: TerminalBufferPosition(col: 1, row: 5),
            active: TerminalBufferPosition(col: 3, row: 5)
        )

        XCTAssertEqual(frame.selectedText(for: selection), "ive")
    }

    func testLineSelectionStoresAbsoluteBufferRows() {
        var frame = TerminalFrame.plainTextPreview("four\nfive\nsix", cols: 6, rows: 3)
        frame.historySize = 5
        frame.displayOffset = 2

        let selection = frame.lineSelection(at: TerminalGridPosition(col: 0, row: 1))

        XCTAssertEqual(selection?.anchor, TerminalBufferPosition(col: 0, row: 4))
        XCTAssertEqual(selection?.active, TerminalBufferPosition(col: 5, row: 4))
    }

    func testWordSelectionStoresAbsoluteBufferRows() {
        var frame = TerminalFrame.plainTextPreview("alpha beta", cols: 10, rows: 2)
        frame.historySize = 4
        frame.displayOffset = 1

        let selection = frame.wordSelection(at: TerminalGridPosition(col: 1, row: 1))

        XCTAssertEqual(selection?.anchor, TerminalBufferPosition(col: 0, row: 4))
        XCTAssertEqual(selection?.active, TerminalBufferPosition(col: 4, row: 4))
    }
}

import XCTest
@testable import TermySwiftEmbed

final class TerminalFrameStoreTests: XCTestCase {
    func testFullUpdateReplacesFrame() {
        let store = TerminalFrameStore()
        let frame = TerminalFrame.plainTextPreview("abc", cols: 3, rows: 1)

        let result = store.apply(TerminalFrameUpdate(
            cols: frame.cols,
            rows: frame.rows,
            cells: frame.cells,
            cursor: nil,
            displayOffset: 0,
            historySize: 0,
            damage: .full
        ))

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.effectiveDamage, .full)
        XCTAssertEqual(store.frame.visibleTextSnapshot(), "abc")
    }

    func testPartialUpdatePatchesOnlyProvidedCells() {
        let store = TerminalFrameStore()
        let initial = TerminalFrame.plainTextPreview("abc", cols: 3, rows: 1)
        store.reset(to: initial)

        var patched = initial.cells[1]
        patched.character = "Z"
        let result = store.apply(TerminalFrameUpdate(
            cols: initial.cols,
            rows: initial.rows,
            cells: [patched],
            cursor: nil,
            displayOffset: 0,
            historySize: 0,
            damage: .partial([TerminalDirtySpan(row: 0, leftCol: 1, rightCol: 1)])
        ))

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.patchedCellCount, 1)
        XCTAssertEqual(store.frame.cell(row: 0, col: 1).map { String($0.character) }, "Z")
        XCTAssertEqual(result.effectiveDamage.dirtyRows, [0])
    }

    func testVisibleContentTracksFullAndPartialUpdates() {
        let store = TerminalFrameStore()
        var blank = TerminalFrame.plainTextPreview("   ", cols: 3, rows: 1)
        blank.cells = blank.cells.map { cell in
            var next = cell
            next.renderText = false
            return next
        }
        store.reset(to: blank)

        XCTAssertFalse(store.hasVisibleContent)

        var visibleCell = blank.cells[1]
        visibleCell.character = "Z"
        visibleCell.renderText = true
        _ = store.apply(TerminalFrameUpdate(
            cols: blank.cols,
            rows: blank.rows,
            cells: [visibleCell],
            cursor: nil,
            displayOffset: 0,
            historySize: 0,
            damage: .partial([TerminalDirtySpan(row: 0, leftCol: 1, rightCol: 1)])
        ))

        XCTAssertTrue(store.hasVisibleContent)

        var clearedCell = visibleCell
        clearedCell.character = " "
        clearedCell.renderText = false
        _ = store.apply(TerminalFrameUpdate(
            cols: blank.cols,
            rows: blank.rows,
            cells: [clearedCell],
            cursor: nil,
            displayOffset: 0,
            historySize: 0,
            damage: .partial([TerminalDirtySpan(row: 0, leftCol: 1, rightCol: 1)])
        ))

        XCTAssertFalse(store.hasVisibleContent)
    }

    func testPartialUpdateMutatesSharedCellStorage() {
        let store = TerminalFrameStore()
        let initial = TerminalFrame.plainTextPreview("abc", cols: 3, rows: 1)
        store.reset(to: initial)
        let observedFrame = store.frame

        var patched = initial.cells[1]
        patched.character = "Z"
        let result = store.apply(TerminalFrameUpdate(
            cols: initial.cols,
            rows: initial.rows,
            cells: [patched],
            cursor: nil,
            displayOffset: 0,
            historySize: 0,
            damage: .partial([TerminalDirtySpan(row: 0, leftCol: 1, rightCol: 1)])
        ))

        XCTAssertTrue(result.changed)
        XCTAssertEqual(observedFrame.cell(row: 0, col: 1).map { String($0.character) }, "Z")
    }

    func testPartialUpdateWithIdenticalCellDoesNotPatchOrRedraw() {
        let store = TerminalFrameStore()
        let initial = TerminalFrame.plainTextPreview("abc", cols: 3, rows: 1)
        store.reset(to: initial)

        let result = store.apply(TerminalFrameUpdate(
            cols: initial.cols,
            rows: initial.rows,
            cells: [initial.cells[1]],
            cursor: nil,
            displayOffset: 0,
            historySize: 0,
            damage: .partial([TerminalDirtySpan(row: 0, leftCol: 1, rightCol: 1)])
        ))

        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.patchedCellCount, 0)
        XCTAssertEqual(result.effectiveDamage, .none)
    }

    func testCursorOnlyUpdateMarksOldAndNewRowsDirty() {
        let store = TerminalFrameStore()
        var initial = TerminalFrame.plainTextPreview("a\nb", cols: 1, rows: 2)
        initial.cursor = TerminalCursor(col: 0, row: 0, style: .block)
        store.reset(to: initial)

        let result = store.apply(TerminalFrameUpdate(
            cols: initial.cols,
            rows: initial.rows,
            cells: [],
            cursor: TerminalCursor(col: 0, row: 1, style: .block),
            displayOffset: 0,
            historySize: 0,
            damage: .none
        ))

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.effectiveDamage.dirtyRows, [0, 1])
        XCTAssertEqual(store.frame.cursor?.row, 1)
    }

    func testDisplayOffsetChangeForcesFullDamage() {
        let store = TerminalFrameStore()
        let initial = TerminalFrame.plainTextPreview("abc", cols: 3, rows: 1)
        store.reset(to: initial)

        let result = store.apply(TerminalFrameUpdate(
            cols: initial.cols,
            rows: initial.rows,
            cells: [],
            cursor: nil,
            displayOffset: 1,
            historySize: 4,
            damage: .none
        ))

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.effectiveDamage, .full)
    }
}

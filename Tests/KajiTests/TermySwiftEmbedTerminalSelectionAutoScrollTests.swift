import XCTest
@testable import TermySwiftEmbed

final class TermySwiftEmbedTerminalSelectionAutoScrollTests: XCTestCase {
    func testTopEdgeScrollsTowardHistory() {
        let metrics = TerminalSelectionAutoScrollMetrics(
            boundsHeight: 240,
            paddingY: 8,
            cellHeight: 20,
            displayOffset: 3,
            historySize: 10
        )

        XCTAssertGreaterThan(TerminalSelectionAutoScrollPolicy.deltaLines(pointY: 230, metrics: metrics), 0)
    }

    func testBottomEdgeScrollsTowardPrompt() {
        let metrics = TerminalSelectionAutoScrollMetrics(
            boundsHeight: 240,
            paddingY: 8,
            cellHeight: 20,
            displayOffset: 3,
            historySize: 10
        )

        XCTAssertLessThan(TerminalSelectionAutoScrollPolicy.deltaLines(pointY: 10, metrics: metrics), 0)
    }

    func testTopBoundaryDoesNotScrollPastHistory() {
        let metrics = TerminalSelectionAutoScrollMetrics(
            boundsHeight: 240,
            paddingY: 8,
            cellHeight: 20,
            displayOffset: 10,
            historySize: 10
        )

        XCTAssertEqual(TerminalSelectionAutoScrollPolicy.deltaLines(pointY: 230, metrics: metrics), 0)
    }

    func testBottomBoundaryDoesNotScrollPastPrompt() {
        let metrics = TerminalSelectionAutoScrollMetrics(
            boundsHeight: 240,
            paddingY: 8,
            cellHeight: 20,
            displayOffset: 0,
            historySize: 10
        )

        XCTAssertEqual(TerminalSelectionAutoScrollPolicy.deltaLines(pointY: 10, metrics: metrics), 0)
    }

    func testMiddleDoesNotScroll() {
        let metrics = TerminalSelectionAutoScrollMetrics(
            boundsHeight: 240,
            paddingY: 8,
            cellHeight: 20,
            displayOffset: 3,
            historySize: 10
        )

        XCTAssertEqual(TerminalSelectionAutoScrollPolicy.deltaLines(pointY: 120, metrics: metrics), 0)
    }
}

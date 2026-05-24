import AppKit
import Testing

@testable import Kaji

struct TerminalPromptClickMovePolicyTests {
    @Test
    func optionOnlyStartsCandidate() {
        #expect(TerminalPromptClickMovePolicy.isCandidate(flags: [.option]))
    }

    @Test
    func otherModifiersDoNotStartCandidate() {
        #expect(!TerminalPromptClickMovePolicy.isCandidate(flags: [.option, .shift]))
        #expect(!TerminalPromptClickMovePolicy.isCandidate(flags: [.command]))
        #expect(!TerminalPromptClickMovePolicy.isCandidate(flags: []))
    }

    @Test
    func smallDragIsSuppressed() {
        #expect(TerminalPromptClickMovePolicy.shouldSuppressDrag(
            start: NSPoint(x: 10, y: 10),
            current: NSPoint(x: 13, y: 14)
        ))
    }

    @Test
    func largerDragIsNotSuppressed() {
        #expect(!TerminalPromptClickMovePolicy.shouldSuppressDrag(
            start: NSPoint(x: 10, y: 10),
            current: NSPoint(x: 16, y: 10)
        ))
    }

    @Test
    func sameRowMovementReturnsArrowCount() {
        let movement = TerminalPromptClickMovePolicy.movement(
            target: NSPoint(x: 50, y: 10),
            cursor: NSPoint(x: 145, y: 10),
            cellSize: CGSize(width: 10, height: 20)
        )

        #expect(movement == .init(keyCode: 123, count: 9))
    }

    @Test
    func sameCellMovementIsHandledWithoutArrows() {
        let movement = TerminalPromptClickMovePolicy.movement(
            target: NSPoint(x: 84, y: 10),
            cursor: NSPoint(x: 82, y: 10),
            cellSize: CGSize(width: 10, height: 20)
        )

        #expect(movement == .init(keyCode: 0, count: 0))
    }

    @Test
    func differentRowsDoNotFallback() {
        let movement = TerminalPromptClickMovePolicy.movement(
            target: NSPoint(x: 42, y: 30),
            cursor: NSPoint(x: 82, y: 10),
            cellSize: CGSize(width: 10, height: 20)
        )

        #expect(movement == nil)
    }
}

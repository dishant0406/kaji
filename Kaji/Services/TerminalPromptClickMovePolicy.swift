import AppKit

enum TerminalPromptClickMovePolicy {
    static let dragTolerance: CGFloat = 4

    struct Movement: Equatable {
        let keyCode: UInt32
        let count: Int

        var isEmpty: Bool {
            count.signum() == 0
        }
    }

    static func isCandidate(flags: NSEvent.ModifierFlags) -> Bool {
        let active = flags.intersection([.command, .control, .option, .shift])
        return active == .option
    }

    static func shouldSuppressDrag(start: NSPoint, current: NSPoint) -> Bool {
        abs(current.x - start.x) <= dragTolerance && abs(current.y - start.y) <= dragTolerance
    }

    static func movement(target: NSPoint, cursor: NSPoint, cellSize: CGSize) -> Movement? {
        guard cellSize.width > 0, cellSize.height > 0 else { return nil }
        let targetRow = Int(floor(target.y / cellSize.height))
        let cursorRow = Int(floor(cursor.y / cellSize.height))
        guard targetRow == cursorRow else { return nil }

        let targetColumn = Int(floor(target.x / cellSize.width))
        let cursorColumn = Int(floor(cursor.x / cellSize.width))
        let delta = targetColumn - cursorColumn
        guard delta != 0 else { return Movement(keyCode: 0, count: 0) }
        return Movement(keyCode: delta < 0 ? 123 : 124, count: abs(delta))
    }
}

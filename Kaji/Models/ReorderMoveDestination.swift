import Foundation

enum ReorderMoveDestination {
    static func arrayMoveOffset(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }
}

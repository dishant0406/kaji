import CoreGraphics

enum ReorderableInsertionResolver {
    static func moveOffset<ID: Hashable>(
        orderedIDs: [ID],
        frames: [ID: CGRect],
        draggedID: ID,
        dragCenter: CGFloat,
        position: (CGRect) -> ReorderableItemPosition
    ) -> Int? {
        guard let sourceIndex = orderedIDs.firstIndex(of: draggedID) else { return nil }

        let candidates = orderedIDs.filter { $0 != draggedID }
        let insertionIndex = candidates.firstIndex { id in
            guard let frame = frames[id] else { return false }
            return dragCenter < position(frame).midpoint
        } ?? candidates.count

        let offset = insertionIndex > sourceIndex ? insertionIndex + 1 : insertionIndex
        return offset == sourceIndex ? nil : offset
    }
}

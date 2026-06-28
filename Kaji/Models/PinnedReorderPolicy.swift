import Foundation

enum PinnedReorderPolicy {
    static func constrainedDestination<Item>(
        sourceIndex: Int,
        destination: Int,
        items: [Item],
        isPinned: (Item) -> Bool
    ) -> Int {
        guard items.indices.contains(sourceIndex) else { return destination }
        let boundedDestination = min(max(destination, 0), items.count)
        let pinnedCount = items.filter(isPinned).count
        if isPinned(items[sourceIndex]) {
            return min(boundedDestination, pinnedCount)
        }
        return max(boundedDestination, pinnedCount)
    }
}

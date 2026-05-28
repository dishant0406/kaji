import Foundation

enum TabHistoryPolicy {
    static let maximumEntries = 64

    static func recordingVisit(
        from previousTabID: UUID?,
        to activeTabID: UUID,
        in history: [UUID],
        existingTabIDs: Set<UUID>,
        limit: Int = maximumEntries
    ) -> [UUID] {
        var next = compacted(
            history,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs,
            limit: limit
        )
        guard limit > 0,
              let previousTabID,
              previousTabID != activeTabID,
              existingTabIDs.contains(previousTabID)
        else { return next }
        next.removeAll { $0 == previousTabID }
        next.append(previousTabID)
        guard next.count > limit else { return next }
        return Array(next.suffix(limit))
    }

    static func compacted(
        _ history: [UUID],
        activeTabID: UUID?,
        existingTabIDs: Set<UUID>,
        limit: Int = maximumEntries
    ) -> [UUID] {
        guard limit > 0 else { return [] }
        var seen = Set<UUID>()
        let newestUnique = history.reversed().reduce(into: [UUID]()) { result, tabID in
            guard tabID != activeTabID,
                  existingTabIDs.contains(tabID),
                  seen.insert(tabID).inserted
            else { return }
            result.append(tabID)
        }
        return Array(newestUnique.reversed().suffix(limit))
    }

    static func previousTabID(
        in history: [UUID],
        activeTabID: UUID?,
        existingTabIDs: Set<UUID>
    ) -> UUID? {
        compacted(
            history,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs
        ).last
    }
}

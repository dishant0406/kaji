import Foundation

struct EditorInactiveResourceSnapshot: Equatable {
    let tabID: UUID
    let isActive: Bool
    let isModified: Bool
    let isLoading: Bool
    let isIncrementalLoading: Bool
    let retainedUTF16Length: Int?
    let recencyRank: Int
}

enum EditorInactiveResourceBudgetPolicy {
    static let maximumRetainedInactiveCleanEditors = 8
    static let maximumRetainedInactiveCleanUTF16 = 2_000_000

    static func tabIDsToRelease(
        snapshots: [EditorInactiveResourceSnapshot],
        maximumRetainedInactiveCleanEditors: Int = Self.maximumRetainedInactiveCleanEditors,
        maximumRetainedInactiveCleanUTF16: Int = Self.maximumRetainedInactiveCleanUTF16
    ) -> Set<UUID> {
        let candidates = snapshots
            .filter { !$0.isActive && !$0.isModified }
            .sorted { lhs, rhs in
                if lhs.recencyRank != rhs.recencyRank {
                    return lhs.recencyRank > rhs.recencyRank
                }
                return lhs.tabID.uuidString < rhs.tabID.uuidString
            }

        var retainedCount = 0
        var retainedUTF16 = 0
        var releaseIDs = Set<UUID>()

        for snapshot in candidates {
            if snapshot.isLoading || snapshot.isIncrementalLoading {
                releaseIDs.insert(snapshot.tabID)
                continue
            }
            guard let length = snapshot.retainedUTF16Length else { continue }
            guard retainedCount < maximumRetainedInactiveCleanEditors,
                  retainedUTF16 + length <= maximumRetainedInactiveCleanUTF16
            else {
                releaseIDs.insert(snapshot.tabID)
                continue
            }
            retainedCount += 1
            retainedUTF16 += length
        }

        return releaseIDs
    }
}

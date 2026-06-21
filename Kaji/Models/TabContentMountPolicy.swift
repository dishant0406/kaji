import Foundation

struct TabContentMountSnapshot: Equatable {
    let tabID: UUID
    let kind: TerminalTab.Kind
    let isActive: Bool
    let isModified: Bool
    let retainedUTF16Length: Int?
    let recencyRank: Int
}

enum TabContentMountPolicy {
    static let maximumRetainedInactiveCleanEditors = 6
    static let maximumRetainedInactiveCleanEditorUTF16 = 1_500_000

    static func mountedTabIDs(
        snapshots: [TabContentMountSnapshot],
        maximumRetainedInactiveCleanEditors: Int = Self.maximumRetainedInactiveCleanEditors,
        maximumRetainedInactiveCleanEditorUTF16: Int = Self.maximumRetainedInactiveCleanEditorUTF16
    ) -> Set<UUID> {
        var mounted = Set<UUID>()

        for snapshot in snapshots where shouldAlwaysMount(snapshot) {
            mounted.insert(snapshot.tabID)
        }

        let cleanEditors = snapshots
            .filter { shouldConsiderRetainingCleanEditor($0, mounted: mounted) }
            .sorted { lhs, rhs in
                if lhs.recencyRank != rhs.recencyRank {
                    return lhs.recencyRank > rhs.recencyRank
                }
                return lhs.tabID.uuidString < rhs.tabID.uuidString
            }

        var retainedCount = 0
        var retainedUTF16 = 0

        for snapshot in cleanEditors {
            guard let length = snapshot.retainedUTF16Length else { continue }
            guard retainedCount < maximumRetainedInactiveCleanEditors,
                  retainedUTF16 + length <= maximumRetainedInactiveCleanEditorUTF16
            else { continue }
            mounted.insert(snapshot.tabID)
            retainedCount += 1
            retainedUTF16 += length
        }

        return mounted
    }

    private static func shouldAlwaysMount(_ snapshot: TabContentMountSnapshot) -> Bool {
        if snapshot.isActive { return true }
        if snapshot.kind.keepsMountedWhenInactive { return true }
        return snapshot.kind == .editor && snapshot.isModified
    }

    private static func shouldConsiderRetainingCleanEditor(_ snapshot: TabContentMountSnapshot, mounted: Set<UUID>) -> Bool {
        guard snapshot.kind == .editor else { return false }
        guard !snapshot.isActive, !snapshot.isModified else { return false }
        guard !mounted.contains(snapshot.tabID) else { return false }
        return snapshot.retainedUTF16Length != nil
    }
}

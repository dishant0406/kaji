import Foundation

extension PaneTabStrip {
    struct TabShortcutSnapshot: Equatable {
        let index: Int
        let displayString: String
        let modifiers: UInt
    }

    struct IndexedTabSnapshot: Identifiable {
        let tab: TabSnapshot
        let shortcut: TabShortcutSnapshot?

        var id: UUID {
            tab.id
        }

        var shortcutIndex: Int? {
            shortcut?.index
        }
    }

    private static let tabShortcutActions: [ShortcutAction] = [
        .selectTab1,
        .selectTab2,
        .selectTab3,
        .selectTab4,
        .selectTab5,
        .selectTab6,
        .selectTab7,
        .selectTab8,
        .selectTab9,
    ]

    @MainActor
    static func indexedSnapshots(from tabs: [TabSnapshot]) -> [IndexedTabSnapshot] {
        tabs.enumerated().map { index, tab in
            IndexedTabSnapshot(
                tab: tab,
                shortcut: tabShortcutSnapshot(for: index)
            )
        }
    }

    @MainActor
    private static func tabShortcutSnapshot(for index: Int) -> TabShortcutSnapshot? {
        guard tabShortcutActions.indices.contains(index) else { return nil }
        let combo = KeyBindingStore.shared.combo(for: tabShortcutActions[index])
        return TabShortcutSnapshot(
            index: index + 1,
            displayString: combo.displayString,
            modifiers: combo.modifiers
        )
    }
}

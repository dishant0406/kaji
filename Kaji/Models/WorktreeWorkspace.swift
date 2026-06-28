import Foundation

@MainActor
@Observable
final class WorktreeWorkspace {
    var tabs: [WorkspaceTab]
    var activeTabID: UUID?
    private var tabHistory: [UUID]

    init(tabs: [WorkspaceTab] = [], activeTabID: UUID? = nil, tabHistory: [UUID] = []) {
        self.tabs = tabs
        self.activeTabID = activeTabID ?? tabs.first?.id
        self.tabHistory = tabHistory
    }

    var activeTab: WorkspaceTab? {
        guard let activeTabID else { return tabs.first }
        return tabs.first { $0.id == activeTabID } ?? tabs.first
    }

    private var tabIDs: Set<UUID> {
        Set(tabs.map(\.id))
    }

    private var firstUnpinnedIndex: Int {
        tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
    }

    func appendTab(_ tab: WorkspaceTab) {
        tabs.append(tab)
        activate(tab.id)
    }

    func insertTab(_ tab: WorkspaceTab, adjacentTo tabID: UUID, side: TabArea.InsertSide) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            appendTab(tab)
            return
        }
        let desiredIndex = side == .left ? index : index + 1
        let insertIndex = max(desiredIndex, firstUnpinnedIndex)
        tabs.insert(tab, at: insertIndex)
        activate(tab.id)
    }

    func selectTab(_ tabID: UUID) {
        guard activeTabID != tabID else { return }
        guard tabIDs.contains(tabID) else { return }
        activate(tabID)
    }

    func selectTabByIndex(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectTab(tabs[index].id)
    }

    func selectNextTab() {
        guard tabs.count > 1,
              let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID })
        else { return }
        selectTab(tabs[(index + 1) % tabs.count].id)
    }

    func selectPreviousTab() {
        guard tabs.count > 1,
              let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID })
        else { return }
        selectTab(tabs[(index - 1 + tabs.count) % tabs.count].id)
    }

    func reorderTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard source.count == 1, let sourceIndex = source.first else { return }
        let constrainedDestination = PinnedReorderPolicy.constrainedDestination(
            sourceIndex: sourceIndex,
            destination: destination,
            items: tabs,
            isPinned: { $0.isPinned }
        )
        tabs.move(fromOffsets: source, toOffset: constrainedDestination)
    }

    func removeTab(_ tabID: UUID) -> WorkspaceTab? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let tab = tabs[index]
        guard !tab.isPinned else { return nil }
        tabs.remove(at: index)
        let existingTabIDs = tabIDs
        tabHistory = TabHistoryPolicy.compacted(
            tabHistory,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs
        )
        guard activeTabID == tabID else { return tab }
        if let previousTabID = TabHistoryPolicy.previousTabID(
            in: tabHistory,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs
        ) {
            activeTabID = previousTabID
            tabHistory = TabHistoryPolicy.compacted(
                tabHistory,
                activeTabID: activeTabID,
                existingTabIDs: existingTabIDs
            )
            return tab
        }
        activeTabID = tabs.last?.id
        tabHistory = TabHistoryPolicy.compacted(
            tabHistory,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs
        )
        return tab
    }

    private func activate(_ tabID: UUID) {
        tabHistory = TabHistoryPolicy.recordingVisit(
            from: activeTabID,
            to: tabID,
            in: tabHistory,
            existingTabIDs: tabIDs
        )
        activeTabID = tabID
    }

    func togglePin(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabs[index]
        tab.isPinned.toggle()
        tabs.remove(at: index)
        if tab.isPinned {
            tabs.insert(tab, at: firstUnpinnedIndex)
            return
        }
        tabs.insert(tab, at: max(firstUnpinnedIndex, 0))
    }
}

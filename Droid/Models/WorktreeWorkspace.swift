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

    private var firstUnpinnedIndex: Int {
        tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
    }

    func appendTab(_ tab: WorkspaceTab) {
        tabs.append(tab)
        if let current = activeTabID, current != tab.id {
            tabHistory.append(current)
        }
        activeTabID = tab.id
    }

    func insertTab(_ tab: WorkspaceTab, adjacentTo tabID: UUID, side: TabArea.InsertSide) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            appendTab(tab)
            return
        }
        let desiredIndex = side == .left ? index : index + 1
        let insertIndex = max(desiredIndex, firstUnpinnedIndex)
        tabs.insert(tab, at: insertIndex)
        if let current = activeTabID, current != tab.id {
            tabHistory.append(current)
        }
        activeTabID = tab.id
    }

    func selectTab(_ tabID: UUID) {
        guard activeTabID != tabID else { return }
        if let current = activeTabID {
            tabHistory.append(current)
        }
        activeTabID = tabID
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
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    func removeTab(_ tabID: UUID) -> WorkspaceTab? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let tab = tabs[index]
        guard !tab.isPinned else { return nil }
        tabs.remove(at: index)
        tabHistory.removeAll { $0 == tabID }
        guard activeTabID == tabID else { return tab }
        let validIDs = Set(tabs.map(\.id))
        while let previous = tabHistory.popLast() {
            if validIDs.contains(previous) {
                activeTabID = previous
                return tab
            }
        }
        activeTabID = tabs.last?.id
        return tab
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

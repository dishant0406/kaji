import Testing
@testable import Kaji

@Suite("WorktreeWorkspace tab history")
@MainActor
struct WorktreeWorkspaceTabHistoryTests {
    private func makeTab() -> WorkspaceTab {
        let area = TabArea(projectPath: "/tmp/kaji-test")
        return WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
    }

    @Test("selecting many workspace tabs keeps close fallback bounded and valid")
    func selectingManyWorkspaceTabsKeepsFallbackValid() throws {
        let first = makeTab()
        let workspace = WorktreeWorkspace(tabs: [first], activeTabID: first.id)
        var tabs = [first]

        for _ in 0 ..< 90 {
            let tab = makeTab()
            tabs.append(tab)
            workspace.appendTab(tab)
        }

        for tab in tabs.reversed() {
            workspace.selectTab(tab.id)
        }

        let activeBeforeClose = try #require(workspace.activeTabID)
        _ = workspace.removeTab(activeBeforeClose)

        #expect(workspace.activeTabID == tabs[1].id)
    }

    @Test("removed workspace tabs are not restored from stale history")
    func removedWorkspaceTabsAreNotRestoredFromHistory() throws {
        let first = makeTab()
        let second = makeTab()
        let third = makeTab()
        let workspace = WorktreeWorkspace(tabs: [first, second, third], activeTabID: first.id)

        workspace.selectTab(second.id)
        workspace.selectTab(third.id)
        _ = workspace.removeTab(second.id)
        _ = workspace.removeTab(third.id)

        #expect(workspace.activeTabID == first.id)
    }
}

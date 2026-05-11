import Foundation
import Testing

@testable import Kaji

@MainActor
struct NotificationNavigatorTests {
    @Test
    func notificationNavigationUsesLivePaneContextBeforeStoredContext() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let pane = TerminalPaneState(projectPath: project.path, title: "Codex")
        let area = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: pane))
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        let appState = AppState(
            selectionStore: NavigatorSelectionStore(),
            terminalViews: NavigatorTerminalViews(),
            workspacePersistence: NavigatorWorkspacePersistence()
        )
        appState.workspaces[key] = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)
        appState.workspaceRoots[key] = workspaceTab.root

        let worktreeStore = WorktreeStore(
            persistence: NavigatorWorktreePersistence(worktrees: [project.id: [worktree]]),
            projects: [project]
        )
        let store = NotificationStore.shared
        store.worktreeStore = worktreeStore
        let notification = KajiNotification(
            paneID: pane.id,
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            worktreePath: "/tmp/wrong",
            source: .aiProvider("codex"),
            title: "Codex",
            body: "Completed task"
        )

        NotificationNavigator.navigate(to: notification, appState: appState, notificationStore: store)

        #expect(appState.activeProjectID == project.id)
        #expect(appState.activeWorktreeID[project.id] == worktree.id)
        #expect(appState.focusedAreaID[key] == area.id)
        #expect(NotificationNavigator.activeTabID(appState: appState) == area.activeTabID)
    }
}

private struct NavigatorSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

private struct NavigatorTerminalViews: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}

private struct NavigatorWorkspacePersistence: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}

private struct NavigatorWorktreePersistence: WorktreePersisting {
    let worktrees: [UUID: [Worktree]]

    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func saveWorktrees(_: [Worktree], projectID _: UUID) throws {}

    func removeWorktrees(projectID _: UUID) throws {}
}

import Foundation
import Testing

@testable import Droid

@MainActor
struct AIActivityStoreTests {
    @Test
    func pruneMissingPanesRemovesStaleActivities() {
        let store = AIActivityStore.shared
        store.reset()

        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktreeID = UUID()
        let pane = TerminalPaneState(projectPath: project.path, title: "shell")
        let area = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: pane))
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)

        let appState = AppState(
            selectionStore: AIActivitySelectionStore(),
            terminalViews: AIActivityTerminalViews(),
            workspacePersistence: AIActivityWorkspacePersistence()
        )
        let key = WorktreeKey(projectID: project.id, worktreeID: worktreeID)
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path
        appState.workspaces[key] = workspace
        appState.workspaceRoots[key] = workspaceTab.root
        appState.focusedAreaID[key] = area.id

        store.start(providerID: "codex", paneID: pane.id, appState: appState, worktreeStore: nil)
        store.start(providerID: "codex", paneID: UUID(), appState: appState, worktreeStore: nil)

        store.pruneMissingPanes(appState: appState)

        #expect(store.hasActiveAgent(projectID: project.id, appState: appState))
        #expect(store.activitiesByPaneID.count == 1)
        #expect(store.activitiesByPaneID[pane.id] != nil)
        store.reset()
    }

    @Test
    func resetClearsActivities() {
        let store = AIActivityStore.shared
        store.reset()

        let project = Project(name: "muxy", path: "/tmp/muxy")
        let appState = AppState(
            selectionStore: AIActivitySelectionStore(),
            terminalViews: AIActivityTerminalViews(),
            workspacePersistence: AIActivityWorkspacePersistence()
        )
        appState.activeProjectID = project.id
        let worktreeID = UUID()
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path

        store.start(providerID: "codex", paneID: UUID(), appState: appState, worktreeStore: nil)
        store.reset()

        #expect(!store.hasActiveAgent(projectID: project.id, appState: appState))
    }
}

private struct AIActivitySelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

private struct AIActivityTerminalViews: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private struct AIActivityWorkspacePersistence: WorkspacePersisting {
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
}

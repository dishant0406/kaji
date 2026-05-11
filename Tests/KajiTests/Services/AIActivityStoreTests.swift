import Foundation
import Testing

@testable import Kaji

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
        store.start(providerID: "claude", paneID: UUID(), appState: appState, worktreeStore: nil)

        store.pruneMissingPanes(appState: appState)

        #expect(store.hasActiveAgent(projectID: project.id))
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

        #expect(!store.hasActiveAgent(projectID: project.id))
    }

    @Test
    func stopByProviderAndContextRemovesMatchingActivity() {
        let store = AIActivityStore.shared
        store.reset()

        let project = Project(name: "muxy", path: "/tmp/muxy")
        let appState = AppState(
            selectionStore: AIActivitySelectionStore(),
            terminalViews: AIActivityTerminalViews(),
            workspacePersistence: AIActivityWorkspacePersistence()
        )
        let worktreeID = UUID()
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path

        store.start(providerID: "codex", paneID: UUID(), appState: appState, worktreeStore: nil)
        #expect(store.hasActiveAgent(projectID: project.id))

        store.stop(providerID: "codex", projectID: project.id, worktreeID: worktreeID)

        #expect(!store.hasActiveAgent(projectID: project.id))
    }

    @Test
    func startAllowsParallelActivitiesForSameProviderAndContext() {
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

        let firstPaneID = UUID()
        let secondPaneID = UUID()

        store.start(providerID: "opencode", paneID: firstPaneID, appState: appState, worktreeStore: nil)
        store.start(providerID: "opencode", paneID: secondPaneID, appState: appState, worktreeStore: nil)

        #expect(store.activitiesByPaneID.count == 2)
        #expect(store.activitiesByPaneID[secondPaneID] != nil)
        #expect(store.activitiesByPaneID[firstPaneID] != nil)
        #expect(AgentRunStore.shared.runs.count == 2)
        #expect(AgentRunStore.shared.runs.allSatisfy { $0.changedFilesAttribution == .sharedWorktree })
    }

    @Test
    func stopByProviderAndProjectRemovesActivitiesAcrossWorktrees() {
        let store = AIActivityStore.shared
        store.reset()

        let project = Project(name: "muxy", path: "/tmp/muxy")
        let appState = AppState(
            selectionStore: AIActivitySelectionStore(),
            terminalViews: AIActivityTerminalViews(),
            workspacePersistence: AIActivityWorkspacePersistence()
        )
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = UUID()
        appState.activeWorktreePath[project.id] = project.path

        store.start(
            providerID: "opencode",
            paneID: UUID(),
            projectID: project.id,
            worktreeID: UUID()
        )
        store.start(
            providerID: "opencode",
            paneID: UUID(),
            projectID: project.id,
            worktreeID: UUID()
        )
        #expect(store.hasActiveAgent(projectID: project.id))

        store.stop(providerID: "opencode", projectID: project.id)

        #expect(!store.hasActiveAgent(projectID: project.id))
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

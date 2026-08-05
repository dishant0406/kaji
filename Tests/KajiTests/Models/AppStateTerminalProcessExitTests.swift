import Foundation
import Testing

@testable import Kaji

@MainActor
struct AppStateTerminalProcessExitTests {
    @Test
    func exitedTerminalCollapsesOwningSplitAreaWithoutConfirmation() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktreeID = UUID()
        let firstPane = TerminalPaneState(projectPath: project.path, title: "shell")
        let firstArea = TabArea(projectPath: project.path, existingTab: TerminalTab(pane: firstPane))
        let exitedPane = TerminalPaneState(projectPath: project.path, title: "server")
        let exitedTab = TerminalTab(pane: exitedPane)
        let exitedArea = TabArea(projectPath: project.path, existingTab: exitedTab)
        let root = SplitNode.split(SplitBranch(direction: .horizontal, first: .tabArea(firstArea), second: .tabArea(exitedArea)))
        let workspaceTab = WorkspaceTab(root: root, focusedAreaID: exitedArea.id)
        let terminalViews = TerminalProcessExitTerminalViews(runningPaneIDs: [exitedPane.id])
        let appState = makeAppState(
            project: project,
            worktreeID: worktreeID,
            workspace: WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id),
            terminalViews: terminalViews
        )

        appState.closeMonitoredTerminal(exitedTab.id, areaID: exitedArea.id, projectID: project.id)

        let remainingRoot = appState.workspaceRoot(for: project.id)
        #expect(remainingRoot?.findArea(id: firstArea.id) != nil)
        #expect(remainingRoot?.findArea(id: exitedArea.id) == nil)
        #expect(remainingRoot?.allAreas().count == 1)
        #expect(appState.pendingProcessAreaClose == nil)
        #expect(terminalViews.removedPaneIDs == [exitedPane.id])
    }

    @Test
    func exitedTerminalClosesContainingWorkspaceTabWithoutConfirmation() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktreeID = UUID()
        let remainingArea = TabArea(projectPath: project.path)
        let remainingWorkspaceTab = WorkspaceTab(root: .tabArea(remainingArea), focusedAreaID: remainingArea.id)
        let exitedPane = TerminalPaneState(projectPath: project.path, title: "server")
        let exitedTab = TerminalTab(pane: exitedPane)
        let exitedArea = TabArea(projectPath: project.path, existingTab: exitedTab)
        let exitedWorkspaceTab = WorkspaceTab(root: .tabArea(exitedArea), focusedAreaID: exitedArea.id)
        let terminalViews = TerminalProcessExitTerminalViews(runningPaneIDs: [exitedPane.id])
        let appState = makeAppState(
            project: project,
            worktreeID: worktreeID,
            workspace: WorktreeWorkspace(
                tabs: [remainingWorkspaceTab, exitedWorkspaceTab],
                activeTabID: exitedWorkspaceTab.id
            ),
            terminalViews: terminalViews
        )

        appState.closeMonitoredTerminal(exitedTab.id, areaID: exitedArea.id, projectID: project.id)

        #expect(appState.workspace(for: project.id)?.tabs.map(\.id) == [remainingWorkspaceTab.id])
        #expect(appState.workspaceRoot(for: project.id)?.findArea(id: remainingArea.id) != nil)
        #expect(appState.pendingProcessTabClose == nil)
        #expect(terminalViews.removedPaneIDs == [exitedPane.id])
    }

    private func makeAppState(
        project: Project,
        worktreeID: UUID,
        workspace: WorktreeWorkspace,
        terminalViews: TerminalProcessExitTerminalViews
    ) -> AppState {
        let appState = AppState(
            selectionStore: TerminalProcessExitSelectionStore(),
            terminalViews: terminalViews,
            workspacePersistence: TerminalProcessExitWorkspacePersistence()
        )
        let key = WorktreeKey(projectID: project.id, worktreeID: worktreeID)
        appState.activeProjectID = project.id
        appState.activeWorktreeID[project.id] = worktreeID
        appState.activeWorktreePath[project.id] = project.path
        appState.workspaces[key] = workspace
        appState.workspaceRoots[key] = workspace.activeTab?.root
        appState.focusedAreaID[key] = workspace.activeTab?.focusedAreaID
        return appState
    }
}

private struct TerminalProcessExitSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

@MainActor
private final class TerminalProcessExitTerminalViews: TerminalViewRemoving {
    private let runningPaneIDs: Set<UUID>
    private(set) var removedPaneIDs: [UUID] = []

    init(runningPaneIDs: Set<UUID> = []) {
        self.runningPaneIDs = runningPaneIDs
    }

    func removeView(for paneID: UUID) {
        removedPaneIDs.append(paneID)
    }

    func needsConfirmQuit(for paneID: UUID) -> Bool {
        runningPaneIDs.contains(paneID)
    }
}

private struct TerminalProcessExitWorkspacePersistence: WorkspacePersisting {
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
}

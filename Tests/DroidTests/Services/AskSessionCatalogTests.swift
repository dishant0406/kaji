import Foundation
import Testing

@testable import Droid

@MainActor
struct AskSessionCatalogTests {
    @Test
    func sessionsDetectProvidersFromTitles() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let codex = TerminalTab(pane: TerminalPaneState(projectPath: project.path, title: "Codex"))
        let shell = TerminalTab(pane: TerminalPaneState(projectPath: project.path, title: "shell"))
        let area = TabArea(projectPath: project.path, existingTab: codex)
        area.insertExistingTab(shell)
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)
        let appState = AppState(
            selectionStore: AskSelectionStore(),
            terminalViews: AskTerminalViews(),
            workspacePersistence: AskWorkspacePersistence()
        )

        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        appState.workspaces[key] = workspace

        let sessions = AskSessionCatalog.sessions(
            projectID: project.id,
            worktreeID: worktree.id,
            worktrees: [worktree],
            appState: appState
        )

        #expect(sessions.count == 2)
        #expect(sessions.first(where: { $0.title == "Codex" })?.provider == .codex)
        #expect(sessions.first(where: { $0.title == "shell" })?.provider == .terminal)
    }

    @Test
    func sessionsDetectProvidersFromStartupCommand() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let codex = TerminalTab(pane: TerminalPaneState(
            projectPath: project.path,
            title: "muxy",
            startupCommand: "codex 'whats this repo about'"
        ))
        let area = TabArea(projectPath: project.path, existingTab: codex)
        let workspaceTab = WorkspaceTab(root: .tabArea(area), focusedAreaID: area.id)
        let workspace = WorktreeWorkspace(tabs: [workspaceTab], activeTabID: workspaceTab.id)
        let appState = AppState(
            selectionStore: AskSelectionStore(),
            terminalViews: AskTerminalViews(),
            workspacePersistence: AskWorkspacePersistence()
        )

        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        appState.workspaces[key] = workspace

        let sessions = AskSessionCatalog.sessions(
            projectID: project.id,
            worktreeID: worktree.id,
            worktrees: [worktree],
            appState: appState
        )

        #expect(sessions.first?.provider == .codex)
    }

    @Test
    func bestMatchFiltersByProvider() {
        let worktreeName = "main"
        let codex = AskSessionOption(
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            paneID: UUID(),
            title: "Codex",
            provider: .codex,
            worktreeName: worktreeName
        )
        let shell = AskSessionOption(
            projectID: UUID(),
            worktreeID: UUID(),
            areaID: UUID(),
            tabID: UUID(),
            paneID: UUID(),
            title: "shell",
            provider: .terminal,
            worktreeName: worktreeName
        )

        #expect(AskSessionCatalog.bestMatch(in: [shell, codex], provider: .codex)?.id == codex.id)
        #expect(AskSessionCatalog.bestMatch(in: [shell, codex], provider: .terminal)?.id == shell.id)
    }
}

private struct AskSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

private struct AskTerminalViews: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private struct AskWorkspacePersistence: WorkspacePersisting {
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
}

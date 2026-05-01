import Foundation
import Testing

@testable import Droid

@MainActor
struct AgentControlCenterTests {
    @Test
    func capabilitiesExposeOnlySupportedReviewActions() {
        let base = item(changedFiles: [], verification: .notStarted)

        #expect(AgentControlCenter.capabilities(for: base).verify == .hidden)
        #expect(AgentControlCenter.capabilities(for: base).openFiles == .hidden)
        #expect(AgentControlCenter.capabilities(for: base).openDiffs == .hidden)

        let file = AgentChangedFile(path: "Droid/App.swift", oldPath: nil, status: .modified, additions: 1, deletions: 0, isBinary: false)
        let withFile = item(changedFiles: [file], verification: .notStarted)

        #expect(AgentControlCenter.capabilities(for: withFile).verify == .available)
        #expect(AgentControlCenter.capabilities(for: withFile).openFiles == .available)
        #expect(AgentControlCenter.capabilities(for: withFile).openDiffs == .available)

        let verifying = item(changedFiles: [file], verification: AgentVerification(
            status: .running,
            command: "swift test",
            output: nil,
            updatedAt: Date()
        ))

        #expect(AgentControlCenter.capabilities(for: verifying).verify == .unavailable("Verification is already running."))
    }

    @Test
    func openFileActivatesRunWorktreeAndRecordsAction() throws {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let appState = AppState(
            selectionStore: ControlSelectionStore(),
            terminalViews: ControlTerminalViews(),
            workspacePersistence: ControlWorkspacePersistence()
        )
        let projectStore = ProjectStore(persistence: ControlProjectPersistence(projects: [project]))
        let worktreeStore = WorktreeStore(
            persistence: ControlWorktreePersistence(worktrees: [project.id: [worktree]]),
            projects: [project]
        )
        let runStore = AgentRunStore.shared
        runStore.reset()
        runStore.start(
            providerID: "codex",
            paneID: UUID(),
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path
        )
        let runID = try #require(runStore.runs.first?.id)
        let file = AgentChangedFile(path: "Droid/App.swift", oldPath: nil, status: .modified, additions: 1, deletions: 0, isBinary: false)
        let controlCenter = AgentControlCenter(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            runStore: runStore
        )

        let result = controlCenter.perform(.openFile(runID, file))

        #expect(result == .succeeded("Opened file."))
        #expect(appState.activeProjectID == project.id)
        #expect(appState.activeWorktreeID[project.id] == worktree.id)
        #expect(appState.workspaceTabs(for: project.id).contains { workspaceTab in
            workspaceTab.root.allAreas().contains { area in
                area.tabs.contains { tab in
                    tab.content.editorState?.filePath == "/tmp/muxy/Droid/App.swift"
                }
            }
        })
        #expect(runStore.run(id: runID)?.actions.last?.kind == .openFile)
        #expect(runStore.run(id: runID)?.actions.last?.status == .succeeded)
    }

    private func item(
        changedFiles: [AgentChangedFile],
        verification: AgentVerification
    ) -> AgentMissionControlItem {
        AgentMissionControlItem(
            id: "run:test",
            runID: UUID(),
            providerID: "codex",
            providerName: "Codex",
            providerIconName: "codex",
            title: "Codex",
            detail: "muxy / main",
            status: .completed,
            timestamp: Date(),
            paneID: UUID(),
            notificationID: nil,
            transcriptEntries: [],
            changedFiles: changedFiles,
            changedFilesAttribution: changedFiles.isEmpty ? .none : .worktreeSnapshot,
            verification: verification
        )
    }
}

private struct ControlSelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

private struct ControlTerminalViews: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}

private struct ControlWorkspacePersistence: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}

private struct ControlProjectPersistence: ProjectPersisting {
    let projects: [Project]

    func loadProjects() throws -> [Project] { projects }
    func saveProjects(_: [Project]) throws {}
}

private struct ControlWorktreePersistence: WorktreePersisting {
    let worktrees: [UUID: [Worktree]]

    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func saveWorktrees(_: [Worktree], projectID _: UUID) throws {}
    func removeWorktrees(projectID _: UUID) throws {}
}

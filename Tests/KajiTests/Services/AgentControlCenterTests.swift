import Foundation
import Testing

@testable import Kaji

@MainActor
struct AgentControlCenterTests {
    @Test
    func capabilitiesExposeOnlySupportedReviewActions() {
        let base = item(changedFiles: [], verification: .notStarted)

        #expect(AgentControlCenter.capabilities(for: base).verify == .hidden)
        #expect(AgentControlCenter.capabilities(for: base).openFiles == .hidden)
        #expect(AgentControlCenter.capabilities(for: base).openDiffs == .hidden)
        #expect(AgentControlCenter.capabilities(for: base).restart == .available)
        #expect(AgentControlCenter.capabilities(for: base).reply == .available)
        #expect(AgentControlCenter.capabilities(for: base).resume == .hidden)
        #expect(AgentControlCenter.capabilities(for: base).approve == .hidden)
        #expect(AgentControlCenter.capabilities(for: base).deny == .hidden)

        let running = item(changedFiles: [], verification: .notStarted, status: .running)
        #expect(AgentControlCenter.capabilities(for: running).reply == .available)
        #expect(AgentControlCenter.capabilities(for: running).stop == .available)

        let resumable = item(changedFiles: [], verification: .notStarted, sessionID: "session-1")
        #expect(AgentControlCenter.capabilities(for: resumable).resume == .available)

        let file = AgentChangedFile(path: "Kaji/App.swift", oldPath: nil, status: .modified, additions: 1, deletions: 0, isBinary: false)
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
        let file = AgentChangedFile(path: "Kaji/App.swift", oldPath: nil, status: .modified, additions: 1, deletions: 0, isBinary: false)
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
                    tab.content.editorState?.filePath == "/tmp/muxy/Kaji/App.swift"
                }
            }
        })
        #expect(runStore.run(id: runID)?.actions.last?.kind == .openFile)
        #expect(runStore.run(id: runID)?.actions.last?.status == .succeeded)
    }

    @Test
    func restartCreatesProviderTabInRunWorktreeAndRecordsAction() throws {
        let context = controlContext()
        let runStore = AgentRunStore()
        runStore.start(
            providerID: "codex",
            paneID: UUID(),
            projectID: context.project.id,
            worktreeID: context.worktree.id,
            worktreePath: context.worktree.path
        )
        let runID = try #require(runStore.runs.first?.id)
        let controlCenter = AgentControlCenter(
            appState: context.appState,
            projectStore: context.projectStore,
            worktreeStore: context.worktreeStore,
            runStore: runStore
        )

        let result = controlCenter.perform(.restart(runID))

        #expect(result == .succeeded("Started new run."))
        #expect(context.appState.workspaceTabs(for: context.project.id).contains { workspaceTab in
            workspaceTab.root.allAreas().contains { area in
                area.tabs.contains { tab in
                    tab.content.pane?.startupCommand?.contains("codex") == true
                }
            }
        })
        #expect(runStore.run(id: runID)?.actions.last?.kind == .restart)
    }

    @Test
    func resumeCreatesProviderResumeTabWhenSessionIsKnown() throws {
        let context = controlContext()
        let runStore = AgentRunStore()
        let run = run(
            providerID: "opencode",
            projectID: context.project.id,
            worktreeID: context.worktree.id,
            worktreePath: context.worktree.path,
            sessionID: "session-1"
        )
        let fileStore = makeFileStore(containing: [run])
        let persistedRunStore = AgentRunStore(fileStore: fileStore)
        let controlCenter = AgentControlCenter(
            appState: context.appState,
            projectStore: context.projectStore,
            worktreeStore: context.worktreeStore,
            runStore: persistedRunStore
        )

        let result = controlCenter.perform(.resume(run.id))

        #expect(result == .succeeded("Resumed run."))
        #expect(context.appState.workspaceTabs(for: context.project.id).contains { workspaceTab in
            workspaceTab.root.allAreas().contains { area in
                area.tabs.contains { tab in
                    tab.content.pane?.startupCommand?.contains("--session") == true
                }
            }
        })
        #expect(persistedRunStore.run(id: run.id)?.actions.last?.kind == .resume)
        _ = runStore
    }

    @Test
    func emptyReplyRecordsUnavailableAction() async throws {
        let context = controlContext()
        let runStore = AgentRunStore()
        runStore.start(providerID: "codex", paneID: UUID(), projectID: context.project.id, worktreeID: context.worktree.id)
        let runID = try #require(runStore.runs.first?.id)
        let controlCenter = AgentControlCenter(
            appState: context.appState,
            projectStore: context.projectStore,
            worktreeStore: context.worktreeStore,
            runStore: runStore
        )

        let result = await controlCenter.performAsync(.reply(runID, "  "))

        #expect(result == .unavailable("Reply is empty."))
        #expect(runStore.run(id: runID)?.actions.last?.kind == .reply)
        #expect(runStore.run(id: runID)?.actions.last?.status == .unavailable)
    }

    @Test
    func replyToCompletedRunResumesSessionWithPromptWhenSessionIsKnown() async throws {
        let context = controlContext()
        let run = run(
            providerID: "opencode",
            projectID: context.project.id,
            worktreeID: context.worktree.id,
            worktreePath: context.worktree.path,
            sessionID: "session-1"
        )
        let fileStore = makeFileStore(containing: [run])
        let persistedRunStore = AgentRunStore(fileStore: fileStore)
        let controlCenter = AgentControlCenter(
            appState: context.appState,
            projectStore: context.projectStore,
            worktreeStore: context.worktreeStore,
            runStore: persistedRunStore
        )

        let result = await controlCenter.performAsync(.reply(run.id, "continue this"))

        #expect(result == .succeeded("Reply queued."))
        #expect(context.appState.workspaceTabs(for: context.project.id).contains { workspaceTab in
            workspaceTab.root.allAreas().contains { area in
                area.tabs.contains { tab in
                    tab.content.pane?.startupCommand?.contains("--session") == true &&
                        tab.content.pane?.startupCommand?.contains("continue this") == true
                }
            }
        })
        #expect(persistedRunStore.run(id: run.id)?.actions.last?.kind == .reply)
    }

    @Test
    func replyToCompletedRunStartsFreshProviderRunWhenSessionIsUnknown() async throws {
        let context = controlContext()
        let run = run(
            providerID: "codex",
            projectID: context.project.id,
            worktreeID: context.worktree.id,
            worktreePath: context.worktree.path,
            sessionID: nil
        )
        let fileStore = makeFileStore(containing: [run])
        let persistedRunStore = AgentRunStore(fileStore: fileStore)
        let controlCenter = AgentControlCenter(
            appState: context.appState,
            projectStore: context.projectStore,
            worktreeStore: context.worktreeStore,
            runStore: persistedRunStore
        )

        let result = await controlCenter.performAsync(.reply(run.id, "follow up"))

        #expect(result == .succeeded("Reply queued."))
        #expect(context.appState.workspaceTabs(for: context.project.id).contains { workspaceTab in
            workspaceTab.root.allAreas().contains { area in
                area.tabs.contains { tab in
                    tab.content.pane?.startupCommand?.contains("codex") == true &&
                        tab.content.pane?.startupCommand?.contains("follow up") == true
                }
            }
        })
        #expect(persistedRunStore.run(id: run.id)?.actions.last?.kind == .reply)
    }

    @Test
    func approveAndDenyRecordUnavailableWithoutPermissionRequest() throws {
        let context = controlContext()
        let runStore = AgentRunStore()
        runStore.start(providerID: "codex", paneID: UUID(), projectID: context.project.id, worktreeID: context.worktree.id)
        let runID = try #require(runStore.runs.first?.id)
        let controlCenter = AgentControlCenter(
            appState: context.appState,
            projectStore: context.projectStore,
            worktreeStore: context.worktreeStore,
            runStore: runStore
        )

        let approveResult = controlCenter.perform(.approve(runID))
        let denyResult = controlCenter.perform(.deny(runID))

        #expect(approveResult == .unavailable("No provider permission request is available for this run."))
        #expect(denyResult == .unavailable("No provider permission request is available for this run."))
        #expect(runStore.run(id: runID)?.actions.map(\.kind).suffix(2) == [.approve, .deny])
    }

    private func item(
        changedFiles: [AgentChangedFile],
        verification: AgentVerification,
        status: AgentMissionControlStatus = .completed,
        sessionID: String? = nil
    ) -> AgentMissionControlItem {
        AgentMissionControlItem(
            id: "run:test",
            runID: UUID(),
            providerID: "codex",
            providerName: "Codex",
            providerIconName: "codex",
            sessionID: sessionID,
            title: "Codex",
            detail: "muxy / main",
            status: status,
            timestamp: Date(),
            paneID: UUID(),
            notificationID: nil,
            transcriptEntries: [],
            changedFiles: changedFiles,
            changedFilesAttribution: changedFiles.isEmpty ? .none : .worktreeSnapshot,
            verification: verification
        )
    }

    private func controlContext() -> ControlContext {
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
        return ControlContext(
            project: project,
            worktree: worktree,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
    }

    private func run(
        providerID: String,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String,
        sessionID: String?
    ) -> AgentRun {
        AgentRun(
            id: UUID(),
            providerID: providerID,
            paneID: UUID(),
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: worktreePath,
            sessionID: sessionID,
            transcriptPath: nil,
            title: providerID,
            status: .completed,
            sourceConfidence: .exactPane,
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted,
            startedAt: Date(),
            lastEventAt: Date(),
            events: [],
            actions: []
        )
    }

    private func makeFileStore(containing runs: [AgentRun]) -> CodableFileStore<[AgentRun]> {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileStore = CodableFileStore<[AgentRun]>(fileURL: directory.appendingPathComponent("agent-runs.json"))
        try? fileStore.save(runs)
        return fileStore
    }
}

private struct ControlContext {
    let project: Project
    let worktree: Worktree
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
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

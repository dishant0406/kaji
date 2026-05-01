import Foundation

@MainActor
final class AgentControlCenter {
    private let appState: AppState
    private let projectStore: ProjectStore
    private let worktreeStore: WorktreeStore
    private let notificationStore: NotificationStore
    private let runStore: AgentRunStore

    init(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        notificationStore: NotificationStore = .shared,
        runStore: AgentRunStore = .shared
    ) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        self.notificationStore = notificationStore
        self.runStore = runStore
    }

    static func capabilities(for item: AgentMissionControlItem) -> AgentRunCapabilities {
        AgentRunCapabilities(
            jump: item.paneID == nil && item.notificationID == nil ? .hidden : .available,
            reply: .hidden,
            stop: .hidden,
            restart: .hidden,
            resume: .hidden,
            verify: verifyCapability(for: item),
            openFiles: openFilesCapability(for: item),
            openDiffs: openDiffsCapability(for: item),
            approve: .hidden,
            deny: .hidden
        )
    }

    func perform(_ action: AgentRunControlAction) -> AgentRunControlResult {
        switch action {
        case let .jump(item):
            jump(to: item)
        case let .verify(runID):
            verify(runID: runID)
        case let .openFile(runID, file):
            openFile(runID: runID, file: file)
        case let .openDiff(runID, file):
            openDiff(runID: runID, file: file)
        }
    }

    private static func verifyCapability(for item: AgentMissionControlItem) -> AgentRunCapability {
        guard item.runID != nil, !item.changedFiles.isEmpty else { return .hidden }
        if item.verification.status == .running {
            return .unavailable("Verification is already running.")
        }
        return .available
    }

    private static func openFilesCapability(for item: AgentMissionControlItem) -> AgentRunCapability {
        guard item.runID != nil else { return .hidden }
        return item.changedFiles.contains { $0.status != .deleted } ? .available : .hidden
    }

    private static func openDiffsCapability(for item: AgentMissionControlItem) -> AgentRunCapability {
        guard item.runID != nil else { return .hidden }
        return item.changedFiles.isEmpty ? .hidden : .available
    }

    private func jump(to item: AgentMissionControlItem) -> AgentRunControlResult {
        guard AgentControlCenter.capabilities(for: item).jump.isAvailable else {
            return record(.unavailable("No pane or notification context is available."), kind: .jump, runID: item.runID)
        }
        AgentMissionControlNavigator.navigate(
            to: item,
            appState: appState,
            worktreeStore: worktreeStore,
            notificationStore: notificationStore
        )
        return record(.succeeded("Jumped to run."), kind: .jump, runID: item.runID)
    }

    private func verify(runID: UUID) -> AgentRunControlResult {
        guard let run = runStore.run(id: runID) else {
            return .unavailable("Run is no longer available.")
        }
        let item = itemProxy(for: run)
        guard AgentControlCenter.capabilities(for: item).verify.isAvailable else {
            return record(.unavailable("Verification is not available for this run."), kind: .verify, runID: runID)
        }
        AgentVerificationRunner.verify(runID: runID, store: runStore)
        return record(.succeeded("Verification started."), kind: .verify, runID: runID)
    }

    private func openFile(runID: UUID, file: AgentChangedFile) -> AgentRunControlResult {
        guard file.status != .deleted else {
            return record(.unavailable("Deleted files cannot be opened directly."), kind: .openFile, runID: runID)
        }
        guard let context = activateContext(for: runID) else {
            return record(.unavailable("Run worktree is unavailable."), kind: .openFile, runID: runID)
        }
        let filePath = (context.worktreePath as NSString).appendingPathComponent(file.path)
        appState.openFile(filePath, projectID: context.projectID)
        return record(.succeeded("Opened file."), kind: .openFile, runID: runID)
    }

    private func openDiff(runID: UUID, file: AgentChangedFile) -> AgentRunControlResult {
        guard let context = activateContext(for: runID) else {
            return record(.unavailable("Run worktree is unavailable."), kind: .openDiff, runID: runID)
        }
        appState.openDiffViewer(
            vcs: VCSTabState(projectPath: context.worktreePath),
            filePath: file.path,
            isStaged: false,
            projectID: context.projectID
        )
        return record(.succeeded("Opened diff."), kind: .openDiff, runID: runID)
    }

    private func record(
        _ result: AgentRunControlResult,
        kind: AgentRunActionKind,
        runID: UUID?
    ) -> AgentRunControlResult {
        guard let runID else { return result }
        switch result {
        case let .succeeded(message):
            runStore.recordAction(runID: runID, kind: kind, status: .succeeded, message: message)
        case let .failed(message):
            runStore.recordAction(runID: runID, kind: kind, status: .failed, message: message)
        case let .unavailable(message):
            runStore.recordAction(runID: runID, kind: kind, status: .unavailable, message: message)
        }
        return result
    }

    private func activateContext(for runID: UUID) -> (projectID: UUID, worktreePath: String)? {
        guard let run = runStore.run(id: runID),
              let projectID = run.projectID,
              let worktreePath = run.worktreePath,
              let project = projectStore.projects.first(where: { $0.id == projectID }),
              let worktree = worktree(for: run, projectID: projectID, worktreePath: worktreePath)
        else { return nil }
        appState.selectProject(project, worktree: worktree)
        return (projectID, worktree.path)
    }

    private func worktree(for run: AgentRun, projectID: UUID, worktreePath: String) -> Worktree? {
        if let worktreeID = run.worktreeID,
           let worktree = worktreeStore.worktree(projectID: projectID, worktreeID: worktreeID)
        {
            return worktree
        }
        return worktreeStore.list(for: projectID).first { $0.path == worktreePath }
    }

    private func itemProxy(for run: AgentRun) -> AgentMissionControlItem {
        AgentRunMissionControlSnapshotBuilder.item(run: run, projects: projectStore.projects, worktrees: worktreeStore.worktrees)
    }
}

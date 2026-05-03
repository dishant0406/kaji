import Foundation

@MainActor
extension ParentAgentController {
    func resolveProject(_ value: String?, projectStore: ProjectStore, appState: AppState) -> Project? {
        if let value, !value.isEmpty {
            let normalized = value.lowercased()
            return projectStore.projects.first { project in
                project.id.uuidString.lowercased() == normalized ||
                    project.name.lowercased() == normalized ||
                    project.path.lowercased() == normalized
            }
        }
        guard let activeProjectID = appState.activeProjectID else { return projectStore.projects.first }
        return projectStore.projects.first { $0.id == activeProjectID }
    }

    func resolveWorktree(_ value: String?, project: Project, worktreeStore: WorktreeStore, appState: AppState) -> Worktree? {
        if let value, !value.isEmpty {
            let normalized = value.lowercased()
            return worktreeStore.list(for: project.id).first { worktree in
                worktree.id.uuidString.lowercased() == normalized ||
                    worktree.name.lowercased() == normalized ||
                    worktree.path.lowercased() == normalized ||
                    worktree.branch?.lowercased() == normalized
            }
        }
        return worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])
    }

    func resolveWorktreeTarget(_ message: ParentAgentEnvelope) -> ParentAgentWorktreeTarget? {
        if let run = resolveRunArgument(message),
           let projectID = run.projectID,
           let worktreePath = run.worktreePath,
           let project = projectStore?.projects.first(where: { $0.id == projectID }),
           let worktree = resolveRunWorktree(run, project: project, worktreePath: worktreePath)
        {
            return ParentAgentWorktreeTarget(project: project, worktree: worktree)
        }
        guard let appState,
              let projectStore,
              let worktreeStore,
              let project = resolveProject(message.arguments?["project"], projectStore: projectStore, appState: appState),
              let worktree = resolveWorktree(
                  message.arguments?["worktree"],
                  project: project,
                  worktreeStore: worktreeStore,
                  appState: appState
              )
        else { return nil }
        return ParentAgentWorktreeTarget(project: project, worktree: worktree)
    }

    func resolveRunWorktree(_ run: AgentRun, project: Project, worktreePath: String) -> Worktree? {
        if let worktreeID = run.worktreeID,
           let worktree = worktreeStore?.worktree(projectID: project.id, worktreeID: worktreeID)
        {
            return worktree
        }
        return worktreeStore?.list(for: project.id).first { $0.path == worktreePath }
    }

    func updateRunChangedFilesIfRequested(_ message: ParentAgentEnvelope, files: [AgentChangedFile]) {
        guard let run = resolveRunArgument(message), let paneID = run.paneID else { return }
        AgentRunStore.shared.setChangedFiles(
            providerID: run.providerID,
            paneID: paneID,
            files: files,
            attribution: .worktreeSnapshot
        )
    }

    func resolveChangedFile(_ message: ParentAgentEnvelope, in run: AgentRun) -> AgentChangedFile? {
        guard let path = message.arguments?["path"]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return run.changedFiles.first
        }
        return run.changedFiles.first { file in
            file.path == path || file.oldPath == path
        }
    }

    func resolveRunArgument(_ message: ParentAgentEnvelope) -> AgentRun? {
        guard let runID = UUID(uuidString: message.arguments?["runID"] ?? "") else { return nil }
        return resolveChildRun(runID)
    }

    func resolveChildRun(_ id: UUID) -> AgentRun? {
        if let run = AgentRunStore.shared.run(id: id) {
            return run
        }
        guard let locator = childRunLocators[id] else { return nil }
        if let run = AgentRunStore.shared.run(providerID: locator.providerID, paneID: locator.paneID) {
            return run
        }
        return AgentRunStore.shared.runs.first { run in
            run.providerID == locator.providerID &&
                run.projectID == locator.projectID &&
                run.worktreeID == locator.worktreeID
        }
    }

    func childContexts(for runs: [AgentRun]) -> [ParentAgentChildRunContext] {
        runs.map { run in
            childContext(for: run, stableID: run.id)
        }
    }

    func childContext(for run: AgentRun, stableID: UUID) -> ParentAgentChildRunContext {
        let feed = ChildAgentFeedStore.shared.recentText(runID: run.id)
        let finalAnswer = ChildAgentFeedStore.shared.finalAnswer(runID: run.id)
        return ParentAgentChildRunContext(
            id: stableID.uuidString,
            provider: AgentMissionControlSnapshotBuilder.providerName(for: run.providerID),
            project: projectName(for: run.projectID),
            status: run.status.rawValue,
            title: run.title,
            lastEvent: finalAnswer ?? feed.last ?? run.events.last?.text,
            recentEvents: Array((feed + run.events.suffix(5).map(\.text)).suffix(8))
        )
    }

    func parentTask(_ message: ParentAgentEnvelope) -> ParentAgentTask? {
        guard let taskID = uuid(from: message.taskID) else { return nil }
        return store.tasks.first { $0.id == taskID }
    }
}

struct ParentAgentTrackedRun {
    let run: AgentRun
    let paneID: UUID
}

struct ParentAgentChildRunLocator: Codable, Hashable {
    let providerID: String
    let paneID: UUID
    let projectID: UUID
    let worktreeID: UUID
}

struct ParentAgentWorktreeTarget {
    let project: Project
    let worktree: Worktree
}

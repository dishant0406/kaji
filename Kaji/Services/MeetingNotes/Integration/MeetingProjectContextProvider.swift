import Foundation

@MainActor
protocol MeetingProjectContextProviding: AnyObject {
    func projectIDs(scope: MeetingProjectContextScope) -> [UUID]
    func context(scope: MeetingProjectContextScope, allowedProjectIDs: Set<UUID>) -> MeetingProjectContext
}

@MainActor
final class MeetingProjectContextProvider: MeetingProjectContextProviding {
    private let appState: AppState
    private let projectStore: ProjectStore
    private let worktreeStore: WorktreeStore
    private let agentRunStore: AgentRunStore
    private let builder: MeetingProjectContextBuilder

    init(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        agentRunStore: AgentRunStore = .shared,
        builder: MeetingProjectContextBuilder = MeetingProjectContextBuilder()
    ) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        self.agentRunStore = agentRunStore
        self.builder = builder
    }

    func projectIDs(scope: MeetingProjectContextScope) -> [UUID] {
        switch scope {
        case .active:
            guard let activeProjectID = appState.activeProjectID,
                  projectStore.projects.contains(where: { $0.id == activeProjectID })
            else { return [] }
            return [activeProjectID]
        case .all:
            return Array(projectStore.projects.prefix(20).map(\.id))
        }
    }

    func context(scope: MeetingProjectContextScope, allowedProjectIDs: Set<UUID>) -> MeetingProjectContext {
        let scopedIDs = Set(projectIDs(scope: scope)).intersection(allowedProjectIDs)
        let inputs = projectStore.projects.compactMap { project -> MeetingProjectContextInput? in
            guard scopedIDs.contains(project.id) else { return nil }
            let worktrees = worktreeStore.list(for: project.id)
            let runs = agentRunStore.runs.filter { $0.projectID == project.id }
                .sorted { $0.lastEventAt > $1.lastEventAt }
                .prefix(12)
            return MeetingProjectContextInput(
                projectID: project.id,
                name: project.name,
                summary: summary(worktrees: worktrees, runs: Array(runs)),
                recentRelativeFilePaths: recentPaths(project: project, worktrees: worktrees, runs: Array(runs))
            )
        }
        return builder.build(from: inputs, allowedProjectIDs: scopedIDs)
    }

    private func summary(worktrees: [Worktree], runs: [AgentRun]) -> String {
        let worktreeMetadata = worktrees.prefix(8).map { worktree in
            [worktree.name, worktree.branch].compactMap(\.self).joined(separator: " @ ")
        }
        let runMetadata = runs.map { run in
            "\(run.providerID): \(run.title) [\(run.status.rawValue)]"
        }
        return (worktreeMetadata + runMetadata).joined(separator: "\n")
    }

    private func recentPaths(project: Project, worktrees: [Worktree], runs: [AgentRun]) -> [String] {
        let roots = ([project.path] + worktrees.map(\.path)).map { root in
            root.hasSuffix("/") ? root : root + "/"
        }
        var seen = Set<String>()
        return runs.flatMap(\.changedFiles).compactMap { file in
            let path: String
            if file.path.hasPrefix("/") {
                guard let root = roots.first(where: { file.path.hasPrefix($0) }) else { return nil }
                path = String(file.path.dropFirst(root.count))
            } else {
                path = file.path
            }
            guard isSafeRelativePath(path), seen.insert(path).inserted else { return nil }
            return path
        }
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty &&
            !path.hasPrefix("/") &&
            !path.contains("\0") &&
            !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
}

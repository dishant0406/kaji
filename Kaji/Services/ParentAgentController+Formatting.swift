import Foundation

@MainActor
extension ParentAgentController {
    func sendBlockedSpawnResult(_ message: ParentAgentEnvelope, toolID: String, reason: String, existingRunID: UUID?) {
        if let taskID = uuid(from: message.taskID) {
            store.append(taskID: taskID, kind: .event, title: "agent.policy", detail: reason)
        }
        let existingRun = existingRunID.flatMap(resolveChildRun)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(
                message: reason,
                childRun: existingRun.map { childContext(for: $0, stableID: existingRunID ?? $0.id) }
            )
        ))
    }

    func performAgentControl(
        _ message: ParentAgentEnvelope,
        toolID: String,
        action: (AgentControlCenter, AgentRun) -> AgentRunControlResult
    ) {
        guard let appState, let projectStore, let worktreeStore else {
            sendToolError(id: toolID, message: "Kaji workspace is unavailable.")
            return
        }
        guard let run = resolveRunArgument(message) else {
            sendToolError(id: toolID, message: "Run is unavailable.")
            return
        }
        let controlCenter = AgentControlCenter(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        sendControlResult(action(controlCenter, run), toolID: toolID)
    }

    func sendControlResult(_ result: AgentRunControlResult, toolID: String) {
        switch result {
        case let .succeeded(message):
            process.send(ParentAgentEnvelope(type: "tool_result", id: toolID, ok: true, result: ParentAgentToolResult(message: message)))
        case let .failed(message),
             let .unavailable(message):
            sendToolError(id: toolID, message: message)
        }
    }

    func projectContexts(_ projects: [Project]) -> [ParentAgentProjectContext] {
        projects.map(projectContext)
    }

    func projectContext(_ project: Project) -> ParentAgentProjectContext {
        let worktrees = worktreeStore?.list(for: project.id).map { worktree in
            worktreeContext(worktree)
        } ?? []
        return ParentAgentProjectContext(
            id: project.id.uuidString,
            name: project.name,
            path: project.path,
            worktrees: worktrees,
            activeWorktreeID: appState?.activeWorktreeID[project.id]?.uuidString
        )
    }

    func worktreeContext(_ worktree: Worktree) -> ParentAgentWorktreeContext {
        ParentAgentWorktreeContext(
            id: worktree.id.uuidString,
            name: worktree.name,
            path: worktree.path,
            branch: worktree.branch,
            isPrimary: worktree.isPrimary
        )
    }

    func changedFileContext(_ file: AgentChangedFile) -> ParentAgentChangedFileContext {
        ParentAgentChangedFileContext(
            path: file.path,
            oldPath: file.oldPath,
            status: file.status.rawValue,
            additions: file.additions,
            deletions: file.deletions,
            isBinary: file.isBinary
        )
    }

    func verificationContext(for runID: UUID) -> ParentAgentVerificationContext? {
        guard let verification = AgentRunStore.shared.run(id: runID)?.verification else { return nil }
        return ParentAgentVerificationContext(
            status: verification.status.rawValue,
            command: verification.command,
            output: verification.output
        )
    }

    func projectName(for id: UUID?) -> String {
        guard let id else { return "Unknown" }
        return projectStore?.projects.first { $0.id == id }?.name ?? "Unknown"
    }

    func sendToolError(id: String, message: String) {
        process.send(ParentAgentEnvelope(type: "tool_result", id: id, ok: false, result: ParentAgentToolResult(message: message)))
    }
}

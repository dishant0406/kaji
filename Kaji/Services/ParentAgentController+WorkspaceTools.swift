import Foundation

@MainActor
extension ParentAgentController {
    func activeProjectContext() -> ParentAgentProjectContext? {
        guard let appState,
              let projectStore,
              let id = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == id })
        else { return nil }
        return projectContext(project)
    }

    func selectProject(_ message: ParentAgentEnvelope, toolID: String) {
        guard let appState,
              let projectStore,
              let worktreeStore
        else {
            sendToolError(id: toolID, message: "Kaji workspace is unavailable.")
            return
        }
        guard let project = resolveProject(message.arguments?["project"], projectStore: projectStore, appState: appState) else {
            sendToolError(id: toolID, message: "No target project is selected or matched.")
            return
        }
        worktreeStore.ensurePrimary(for: project)
        guard let worktree = resolveWorktree(
            message.arguments?["worktree"],
            project: project,
            worktreeStore: worktreeStore,
            appState: appState
        )
        else {
            sendToolError(id: toolID, message: "No worktree is available for \(project.name).")
            return
        }
        appState.selectProject(project, worktree: worktree)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(
                activeProject: projectContext(project),
                message: "Selected \(project.name) / \(worktree.name)."
            )
        ))
    }

    func selectWorktree(_ message: ParentAgentEnvelope, toolID: String) {
        guard let appState,
              let projectStore,
              let worktreeStore
        else {
            sendToolError(id: toolID, message: "Kaji workspace is unavailable.")
            return
        }
        guard let project = resolveProject(message.arguments?["project"], projectStore: projectStore, appState: appState) else {
            sendToolError(id: toolID, message: "No target project is selected or matched.")
            return
        }
        guard let worktree = resolveWorktree(
            message.arguments?["worktree"],
            project: project,
            worktreeStore: worktreeStore,
            appState: appState
        )
        else {
            sendToolError(id: toolID, message: "No matching worktree is available for \(project.name).")
            return
        }
        appState.selectWorktree(projectID: project.id, worktree: worktree)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(
                activeProject: projectContext(project),
                message: "Selected worktree \(worktree.name)."
            )
        ))
    }

    func openTerminal(_ message: ParentAgentEnvelope, toolID: String, split: Bool) {
        guard let appState,
              let projectStore,
              let worktreeStore
        else {
            sendToolError(id: toolID, message: "Kaji workspace is unavailable.")
            return
        }
        guard let project = resolveProject(message.arguments?["project"], projectStore: projectStore, appState: appState) else {
            sendToolError(id: toolID, message: "No target project is selected or matched.")
            return
        }
        worktreeStore.ensurePrimary(for: project)
        guard let worktree = resolveWorktree(
            message.arguments?["worktree"],
            project: project,
            worktreeStore: worktreeStore,
            appState: appState
        )
        else {
            sendToolError(id: toolID, message: "No worktree is available for \(project.name).")
            return
        }
        appState.selectProject(project, worktree: worktree)
        let command = message.arguments?["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = message.arguments?["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Terminal"
        if command.isEmpty {
            if split {
                appState.splitFocusedArea(direction: splitDirection(from: message.arguments?["direction"]), projectID: project.id)
            } else {
                appState.createTab(projectID: project.id)
            }
        } else if split {
            appState.createCommandSplit(projectID: project.id, title: title, command: command)
        } else {
            appState.createCommandTab(projectID: project.id, title: title, command: command)
        }
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(
                activeProject: projectContext(project),
                message: split ? "Opened split in \(project.name)." : "Opened terminal in \(project.name)."
            )
        ))
    }
}

import Foundation

@MainActor
enum KajiAgentBasicHostTools {
    static func activeContext(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        return KajiAgentHostToolResult.text([
            "Active project: \(context.project.name)",
            "Project path: \(context.project.path)",
            "Worktree: \(context.worktree.name)",
            "Worktree path: \(context.worktree.path)",
        ].joined(separator: "\n"))
    }

    static func openFile(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        guard let rawPath = frame.arguments?["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            return KajiAgentHostToolResult.error("path is required.")
        }
        guard let path = KajiAgentWorkspacePathResolver.resolve(rawPath, rootPath: context.worktree.path) else {
            return KajiAgentHostToolResult.error("File path is outside the active Kaji worktree.")
        }
        context.appState.selectProject(context.project, worktree: context.worktree)
        context.appState.openFile(path, projectID: context.project.id)
        return KajiAgentHostToolResult.text("Opened \(path).")
    }

    static func openTerminal(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        let title = frame.arguments?["title"]?.stringValue?.nilIfEmpty ?? "Terminal"
        let command = frame.arguments?["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        context.appState.selectProject(context.project, worktree: context.worktree)
        if command.isEmpty {
            context.appState.createTab(projectID: context.project.id)
        } else {
            context.appState.createCommandTab(projectID: context.project.id, title: title, command: command)
        }
        return KajiAgentHostToolResult.text(command.isEmpty ? "Opened terminal." : "Opened command terminal.")
    }
}

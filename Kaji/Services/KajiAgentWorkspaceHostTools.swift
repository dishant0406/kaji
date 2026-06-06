import Foundation

@MainActor
enum KajiAgentWorkspaceHostTools {
    static func openTabs(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        ),
            let workspace = context.appState.workspace(for: context.project.id)
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        let rows = workspace.tabs.enumerated().map { index, tab in
            let active = tab.id == workspace.activeTabID ? " active" : ""
            return "\(index + 1). \(tab.title) kind=\(tab.kind.rawValue) id=\(tab.id.uuidString)\(active)"
        }
        let text = rows.isEmpty ? "No open tabs." : "Open tabs for \(context.project.name):\n" + rows.joined(separator: "\n")
        return KajiAgentHostToolResult.text(text, details: .object([
            "projectID": .string(context.project.id.uuidString),
            "activeTabID": workspace.activeTabID.map { .string($0.uuidString) } ?? .null,
            "tabs": .array(workspace.tabs.map { tab in
                .object([
                    "id": .string(tab.id.uuidString),
                    "title": .string(tab.title),
                    "kind": .string(tab.kind.rawValue),
                    "active": .bool(tab.id == workspace.activeTabID),
                ])
            }),
        ]))
    }

    static func terminalPanes(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        ),
            let workspace = context.appState.workspace(for: context.project.id)
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        let panes = workspace.tabs.flatMap { tab in tab.root.allAreas().flatMap { area in area.tabs.compactMap(\.content.pane) } }
        let rows = panes.enumerated().map { index, pane in
            "\(index + 1). \(pane.title) id=\(pane.id.uuidString) cwd=\(pane.projectPath)"
        }
        let text = rows.isEmpty ? "No terminal panes are open." : "Open terminal panes:\n" + rows.joined(separator: "\n")
        return KajiAgentHostToolResult.text(text, details: .object([
            "panes": .array(panes.map { pane in
                .object(["id": .string(pane.id.uuidString), "title": .string(pane.title), "projectPath": .string(pane.projectPath)])
            }),
        ]))
    }

    static func worktreeStatus(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        do {
            async let branch = GitProcessRunner.runGit(
                repoPath: context.worktree.path,
                arguments: ["branch", "--show-current"],
                lineLimit: 20
            )
            async let status = GitProcessRunner.runGit(
                repoPath: context.worktree.path,
                arguments: ["status", "--short", "--branch"],
                lineLimit: 200
            )
            let result = try await (branch, status)
            let branchName = result.0.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "detached"
            let statusText = result.1.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Clean worktree."
            return KajiAgentHostToolResult.text("Branch: \(branchName)\n\(statusText)", details: .object([
                "branch": .string(branchName),
                "status": .string(statusText),
                "path": .string(context.worktree.path),
            ]))
        } catch {
            return KajiAgentHostToolResult.error(error.localizedDescription)
        }
    }
}

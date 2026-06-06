import Foundation

@MainActor
enum KajiAgentWorkspaceStateSnapshot {
    static func activeWorkspace(
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> (context: KajiAgentWorkspaceContext, workspace: WorktreeWorkspace)? {
        guard let context = KajiAgentWorkspaceContextResolver.active(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        ), let workspace = context.appState.workspace(for: context.project.id)
        else { return nil }
        return (context, workspace)
    }

    static func activeEditor(in workspace: WorktreeWorkspace) -> EditorTabState? {
        workspace.activeTab?.activeContent?.content.editorState
    }

    static func editorState(for path: String, in workspace: WorktreeWorkspace) -> EditorTabState? {
        let normalized = (path as NSString).standardizingPath
        for tab in workspace.tabs {
            for area in tab.root.allAreas() {
                for pane in area.tabs {
                    guard let state = pane.content.editorState else { continue }
                    if (state.filePath as NSString).standardizingPath == normalized {
                        return state
                    }
                }
            }
        }
        return nil
    }

    static func activeVCSTab(in workspace: WorktreeWorkspace, fallbackPath: String) -> VCSTabState {
        for tab in workspace.tabs {
            for area in tab.root.allAreas() {
                for pane in area.tabs {
                    if let state = pane.content.vcsState {
                        return state
                    }
                    if let state = pane.content.diffViewerState?.vcs {
                        return state
                    }
                }
            }
        }
        return VCSTabState(projectPath: fallbackPath)
    }

    static func relativePath(_ path: String, root: String) -> String? {
        let full = (path as NSString).standardizingPath
        let base = (root as NSString).standardizingPath
        if full == base { return "" }
        guard full.hasPrefix(base + "/") else { return nil }
        return String(full.dropFirst(base.count + 1))
    }

    static func resolveRelativePath(_ rawPath: String, root: String) -> String? {
        guard let resolved = KajiAgentWorkspacePathResolver.resolve(rawPath, rootPath: root) else { return nil }
        return relativePath(resolved, root: root)
    }
}

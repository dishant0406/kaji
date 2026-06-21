import SwiftUI

struct EditorAreaHostView: View {
    let tab: TerminalTab
    let focused: Bool
    let onFocus: () -> Void
    @Environment(\.activeWorktreeKey) private var worktreeKey
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore

    var body: some View {
        if let editorState = tab.content.editorState {
            EditorPane(
                state: editorState,
                focused: focused,
                onFocus: onFocus,
                project: activeProject,
                worktree: activeWorktree
            )
        }
    }

    private var activeProject: Project? {
        guard let projectID = appState.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == projectID }
    }

    private var activeWorktree: Worktree? {
        guard let project = activeProject else { return nil }
        if let worktreeKey {
            return worktreeStore.worktrees[project.id]?.first { $0.id == worktreeKey.worktreeID }
        }
        return worktreeStore.primary(for: project.id)
    }
}

import Foundation

@MainActor
enum KajiAgentHostToolRegistry {
    static let definitions = KajiAgentHostToolCatalog.definitions
    static let uriSchemes = KajiAgentHostToolCatalog.uriSchemes

    static func execute(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) async -> KajiAgentToolResult {
        switch frame.toolName {
        case "kaji_get_active_context":
            KajiAgentBasicHostTools.activeContext(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_open_file":
            KajiAgentBasicHostTools.openFile(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_open_terminal":
            KajiAgentBasicHostTools.openTerminal(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_get_open_tabs":
            KajiAgentWorkspaceHostTools.openTabs(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_get_editor_selection":
            KajiAgentWorkspaceEditorHostTools.editorSelection(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_get_visible_file_context":
            KajiAgentWorkspaceEditorHostTools.visibleFileContext(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        case "kaji_get_terminal_panes":
            KajiAgentWorkspaceHostTools.terminalPanes(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_get_worktree_status":
            await KajiAgentWorkspaceHostTools.worktreeStatus(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_show_diff":
            await KajiAgentWorkspaceDiffHostTools.showDiff(
                frame,
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        case "kaji_open_diff":
            await KajiAgentWorkspaceDiffHostTools.openDiff(
                frame,
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        case "kaji_focus_file_range":
            KajiAgentWorkspaceEditorHostTools.focusFileRange(
                frame,
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        case "kaji_report_diagnostics":
            KajiAgentWorkspaceEditorHostTools.reportDiagnostics(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        case "kaji_fff_find":
            await KajiAgentFFFHostTools.find(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        case "kaji_fff_search":
            await KajiAgentFFFHostTools.search(frame, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        default:
            KajiAgentHostToolResult.error("Unsupported Kaji host tool: \(frame.toolName ?? "unknown")")
        }
    }

    static func resolveURI(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentHostURIResult {
        let context = KajiAgentWorkspaceContextResolver.active(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        return KajiAgentHostURIResolver.resolve(frame, rootPath: context?.worktree.path)
    }
}

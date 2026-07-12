import SwiftUI

struct TabContentView: View {
    let tab: TerminalTab
    let focused: Bool
    let visible: Bool
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onClosePane: () -> Void
    let onSplitRequest: (SplitDirection, SplitPosition) -> Void
    @Environment(\.activeWorktreeKey) private var worktreeKey
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore

    var body: some View {
        switch tab.content {
        case let .terminal(pane):
            TerminalPane(
                state: pane,
                focused: focused,
                visible: visible,
                onFocus: onFocus,
                onProcessExit: onProcessExit,
                onSplitRequest: onSplitRequest
            )
        case let .vcs(vcsState):
            VCSTabView(state: vcsState, focused: focused, onFocus: onFocus)
        case .editor:
            EmptyView()
        case let .filePreview(previewState):
            FilePreviewPane(state: previewState, onFocus: onFocus)
        case let .diffViewer(diffState):
            DiffViewerPane(state: diffState, focused: focused, onFocus: onFocus)
        case .problems:
            ProblemsPanel(
                store: DiagnosticsStore.shared,
                onOpenDiagnostic: { diagnostic in
                    guard let project = activeProject else { return }
                    appState.openFile(diagnostic.filePath, projectID: project.id)
                },
                onClose: onClosePane
            )
        case let .parentAgent(state):
            KajiAgentHome(scope: state.scope, projectPathOverride: state.projectPath, initialSessionPath: state.initialSessionPath)
        case let .codeGraph(state):
            KajiCodeGraphPane(state: state)
        case let .browser(state):
            BrowserPane(
                state: state,
                sessionID: worktreeKey?.worktreeID.uuidString,
                closeOnDisappear: true,
                managesBrowserControl: true,
                paneIsVisible: visible,
                respondsToKeyboardCommands: focused,
                onClosePane: onClosePane
            )
        }
    }

    private var activeProject: Project? {
        guard let projectID = appState.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == projectID }
    }
}

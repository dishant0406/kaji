import Foundation

@MainActor
@Observable
final class TerminalTab: Identifiable {
    enum Kind: String, Codable {
        case terminal
        case vcs
        case editor
        case filePreview
        case diffViewer
        case problems
        case parentAgent
        case codeGraph
        case browser
    }

    enum Content {
        case terminal(TerminalPaneState)
        case vcs(VCSTabState)
        case editor(EditorTabState)
        case filePreview(FilePreviewTabState)
        case diffViewer(DiffViewerTabState)
        case problems(ProblemsTabState)
        case parentAgent(ParentAgentTabState)
        case codeGraph(KajiCodeGraphTabState)
        case browser(BrowserPaneState)

        var kind: Kind {
            switch self {
            case .terminal: .terminal
            case .vcs: .vcs
            case .editor: .editor
            case .filePreview: .filePreview
            case .diffViewer: .diffViewer
            case .problems: .problems
            case .parentAgent: .parentAgent
            case .codeGraph: .codeGraph
            case .browser: .browser
            }
        }

        var pane: TerminalPaneState? {
            guard case let .terminal(pane) = self else { return nil }
            return pane
        }

        var vcsState: VCSTabState? {
            guard case let .vcs(state) = self else { return nil }
            return state
        }

        var editorState: EditorTabState? {
            guard case let .editor(state) = self else { return nil }
            return state
        }

        var filePreviewState: FilePreviewTabState? {
            guard case let .filePreview(state) = self else { return nil }
            return state
        }

        var diffViewerState: DiffViewerTabState? {
            guard case let .diffViewer(state) = self else { return nil }
            return state
        }

        var codeGraphState: KajiCodeGraphTabState? {
            guard case let .codeGraph(state) = self else { return nil }
            return state
        }

        var browserState: BrowserPaneState? {
            guard case let .browser(state) = self else { return nil }
            return state
        }

        var parentAgentState: ParentAgentTabState? {
            guard case let .parentAgent(state) = self else { return nil }
            return state
        }

        var projectPath: String {
            switch self {
            case let .terminal(pane): pane.projectPath
            case let .vcs(state): state.projectPath
            case let .editor(state): state.projectPath
            case let .filePreview(state): state.projectPath
            case let .diffViewer(state): state.projectPath
            case let .problems(state): state.projectPath
            case let .parentAgent(state): state.projectPath
            case let .codeGraph(state): state.projectPath
            case let .browser(state): state.projectPath
            }
        }
    }

    let id = UUID()
    var customTitle: String?
    var colorID: String?
    var isPinned: Bool = false
    let content: Content

    var kind: Kind { content.kind }

    var title: String {
        if let customTitle {
            return customTitle
        }
        switch content {
        case let .terminal(pane):
            return pane.title
        case .vcs:
            return "Git Diff"
        case let .editor(state):
            return state.displayTitle
        case let .filePreview(state):
            return state.displayTitle
        case let .diffViewer(state):
            return state.displayTitle
        case .problems:
            return "Problems"
        case .parentAgent:
            return "Kaji"
        case .codeGraph:
            return "Code Graph"
        case let .browser(state):
            return state.title
        }
    }

    init(pane: TerminalPaneState) {
        content = .terminal(pane)
    }

    init(vcsState: VCSTabState) {
        content = .vcs(vcsState)
    }

    init(editorState: EditorTabState) {
        content = .editor(editorState)
    }

    init(filePreviewState: FilePreviewTabState) {
        content = .filePreview(filePreviewState)
    }

    init(diffViewerState: DiffViewerTabState) {
        content = .diffViewer(diffViewerState)
    }

    init(problemsState: ProblemsTabState) {
        content = .problems(problemsState)
    }

    init(parentAgentState: ParentAgentTabState) {
        content = .parentAgent(parentAgentState)
    }

    init(codeGraphState: KajiCodeGraphTabState) {
        content = .codeGraph(codeGraphState)
    }

    init(browserState: BrowserPaneState) {
        content = .browser(browserState)
    }

    init(restoring snapshot: TerminalTabSnapshot, projectID: UUID? = nil, worktreeID: UUID? = nil) {
        customTitle = snapshot.customTitle
        colorID = snapshot.colorID
        isPinned = snapshot.isPinned
        switch snapshot.kind {
        case .terminal:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        case .vcs:
            content = .vcs(VCSTabState(projectPath: snapshot.projectPath))
        case .editor:
            if let filePath = snapshot.filePath {
                content = .editor(EditorTabState(projectPath: snapshot.projectPath, filePath: filePath))
            } else {
                content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
            }
        case .filePreview:
            if let filePath = snapshot.filePath {
                content = .filePreview(FilePreviewTabState(
                    projectPath: snapshot.projectPath,
                    filePath: filePath,
                    kind: FilePreviewClassifier.previewKind(for: filePath) ?? .quickLook
                ))
            } else {
                content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
            }
        case .diffViewer:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        case .problems:
            content = .problems(ProblemsTabState(projectPath: snapshot.projectPath))
        case .parentAgent:
            content = .terminal(TerminalPaneState(
                projectPath: snapshot.projectPath,
                title: "KajiCode",
                startupCommand: KajiCodeCommandBuilder.splitCommand()
            ))
        case .codeGraph:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        case .browser:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        }
    }

    func snapshot() -> TerminalTabSnapshot {
        TerminalTabSnapshot(
            kind: content.kind,
            customTitle: customTitle,
            colorID: colorID,
            isPinned: isPinned,
            projectPath: content.projectPath,
            paneTitle: content.pane?.title,
            filePath: content.editorState?.filePath ?? content.filePreviewState?.filePath,
            browserURL: content.browserState?.url,
            browserPages: content.browserState?.pageSnapshots,
            selectedBrowserPageID: content.browserState?.selectedPageID,
            browserDeviceProfileID: content.browserState?.selectedDeviceProfileID,
            parentAgentID: content.parentAgentState?.id,
            parentAgentProjectID: content.parentAgentState?.projectID,
            parentAgentWorktreeID: content.parentAgentState?.worktreeID,
            parentAgentInitialSessionPath: content.parentAgentState?.initialSessionPath
        )
    }
}

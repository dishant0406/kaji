import Foundation

@MainActor
enum KajiAgentWorkspaceEditorHostTools {
    static func editorSelection(appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentToolResult {
        guard let snapshot = KajiAgentWorkspaceStateSnapshot.activeWorkspace(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        ), let state = KajiAgentWorkspaceStateSnapshot.activeEditor(in: snapshot.workspace)
        else {
            return KajiAgentHostToolResult.error("No active native editor tab.")
        }
        let selection = state.currentSelection
        let text = selection.isEmpty ? "No text is selected in the active editor." : selection
        return KajiAgentHostToolResult.text(text, details: .object([
            "path": .string(state.filePath),
            "relativePath": .string(KajiAgentWorkspaceStateSnapshot
                .relativePath(state.filePath, root: snapshot.context.worktree.path) ?? state.filePath),
            "line": .number(Double(state.cursorLine)),
            "column": .number(Double(state.cursorColumn)),
            "selectionLength": .number(Double(state.cursorPosition.selectionLength)),
            "selectedText": .string(selection),
        ]))
    }

    static func visibleFileContext(appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentToolResult {
        guard let snapshot = KajiAgentWorkspaceStateSnapshot.activeWorkspace(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        ), let content = snapshot.workspace.activeTab?.activeContent
        else {
            return KajiAgentHostToolResult.error("No active Kaji project.")
        }
        if let state = content.content.editorState {
            return editorContext(state, root: snapshot.context.worktree.path)
        }
        if let state = content.content.diffViewerState {
            return diffContext(state)
        }
        if let state = content.content.filePreviewState {
            return KajiAgentHostToolResult.text("Active file preview: \(state.filePath)", details: .object([
                "kind": .string("filePreview"),
                "path": .string(state.filePath),
            ]))
        }
        return KajiAgentHostToolResult.text("Active pane: \(content.title) kind=\(content.kind.rawValue)", details: .object([
            "kind": .string(content.kind.rawValue),
            "title": .string(content.title),
        ]))
    }

    static func focusFileRange(
        _ frame: KajiAgentRPCFrame,
        appState: AppState?,
        projectStore: ProjectStore?,
        worktreeStore: WorktreeStore?
    ) -> KajiAgentToolResult {
        guard let snapshot = KajiAgentWorkspaceStateSnapshot.activeWorkspace(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else { return KajiAgentHostToolResult.error("No active Kaji project.") }
        guard let rawPath = frame.arguments?["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            return KajiAgentHostToolResult.error("path is required.")
        }
        guard let absolutePath = KajiAgentWorkspacePathResolver.resolve(rawPath, rootPath: snapshot.context.worktree.path) else {
            return KajiAgentHostToolResult.error("File path is outside the active Kaji worktree.")
        }
        let line = max(1, Int(frame.arguments?["line"]?.numberValue ?? 1))
        let column = max(1, Int(frame.arguments?["column"]?.numberValue ?? 1))
        snapshot.context.appState.selectProject(snapshot.context.project, worktree: snapshot.context.worktree)
        snapshot.context.appState.openFile(absolutePath, projectID: snapshot.context.project.id)
        if let editor = KajiAgentWorkspaceStateSnapshot.editorState(for: absolutePath, in: snapshot.workspace) {
            editor.navigate(to: EditorLineNavigationRequest(line: line, column: column))
        }
        return KajiAgentHostToolResult.text("Focused \(absolutePath):\(line):\(column).")
    }

    static func reportDiagnostics(appState: AppState?, projectStore: ProjectStore?, worktreeStore: WorktreeStore?) -> KajiAgentToolResult {
        guard let snapshot = KajiAgentWorkspaceStateSnapshot.activeWorkspace(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        else { return KajiAgentHostToolResult.error("No active Kaji project.") }
        let root = (snapshot.context.worktree.path as NSString).standardizingPath
        let diagnostics = DiagnosticsStore.shared.allDiagnostics.filter { diagnostic in
            (diagnostic.filePath as NSString).standardizingPath.hasPrefix(root + "/")
        }
        let rows = diagnostics.prefix(200).map { diagnostic in
            "\(diagnostic.relativePath):\(diagnostic.line):\(diagnostic.column) \(severityText(diagnostic.severity)): \(diagnostic.message)"
        }
        let text = rows.isEmpty ? "No diagnostics reported for the active worktree." : rows.joined(separator: "\n")
        return KajiAgentHostToolResult.text(text, details: .object([
            "count": .number(Double(diagnostics.count)),
            "diagnostics": .array(diagnostics.prefix(200).map(diagnosticJSON)),
        ]))
    }

    private static func editorContext(_ state: EditorTabState, root: String) -> KajiAgentToolResult {
        let range = visibleLineRange(state)
        let body = state.backingStore?.textForRange(range) ?? ""
        let heading = "Active editor: \(state.filePath) lines \(range.lowerBound + 1)-\(range.upperBound)"
        return KajiAgentHostToolResult.text([heading, body].filter { !$0.isEmpty }.joined(separator: "\n"), details: .object([
            "kind": .string("editor"),
            "path": .string(state.filePath),
            "relativePath": .string(KajiAgentWorkspaceStateSnapshot.relativePath(state.filePath, root: root) ?? state.filePath),
            "lineStart": .number(Double(range.lowerBound + 1)),
            "lineEnd": .number(Double(range.upperBound)),
            "cursorLine": .number(Double(state.cursorLine)),
            "cursorColumn": .number(Double(state.cursorColumn)),
            "source": .string(contextSource(state)),
        ]))
    }

    private static func diffContext(_ state: DiffViewerTabState) -> KajiAgentToolResult {
        let files = state.showsAllChanges ? state.files.map(\.path) : [state.filePath].filter { !$0.isEmpty }
        return KajiAgentHostToolResult.text("Active diff viewer: \(state.displayTitle)", details: .object([
            "kind": .string("diffViewer"),
            "title": .string(state.displayTitle),
            "files": .array(files.map { .string($0) }),
            "visibleFiles": .array(state.visibleFilePaths.sorted().map { .string($0) }),
        ]))
    }

    private static func visibleLineRange(_ state: EditorTabState) -> Range<Int> {
        guard let store = state.backingStore else { return 0 ..< 0 }
        if state.markdownEditorLineHeight > 0, state.markdownEditorViewportHeight > 0 {
            let first = max(0, Int(floor(state.markdownEditorScrollY / state.markdownEditorLineHeight)))
            let count = max(1, Int(ceil(state.markdownEditorViewportHeight / state.markdownEditorLineHeight)))
            return first ..< min(store.lineCount, first + count)
        }
        let center = max(0, state.cursorLine - 1)
        let start = max(0, center - 40)
        return start ..< min(store.lineCount, center + 41)
    }

    private static func contextSource(_ state: EditorTabState) -> String {
        state.markdownEditorLineHeight > 0 && state.markdownEditorViewportHeight > 0 ? "viewport" : "cursor_window"
    }

    private static func diagnosticJSON(_ diagnostic: EditorDiagnostic) -> KajiAgentJSONValue {
        .object([
            "path": .string(diagnostic.filePath),
            "relativePath": .string(diagnostic.relativePath),
            "line": .number(Double(diagnostic.line)),
            "column": .number(Double(diagnostic.column)),
            "severity": .string(severityText(diagnostic.severity)),
            "message": .string(diagnostic.message),
            "source": diagnostic.source.map { .string($0) } ?? .null,
        ])
    }

    private static func severityText(_ severity: EditorDiagnosticSeverity) -> String {
        switch severity {
        case .error: "error"
        case .warning: "warning"
        case .information: "information"
        case .hint: "hint"
        }
    }
}

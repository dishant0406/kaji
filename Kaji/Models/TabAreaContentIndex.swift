import Foundation

@MainActor
struct TabAreaContentIndex {
    private struct DiffKey: Hashable {
        let filePath: String
        let isStaged: Bool
    }

    private var editorTabIDsByFilePath: [String: UUID] = [:]
    private var filePreviewTabIDsByFilePath: [String: UUID] = [:]
    private var externalEditorTabIDsByFilePath: [String: UUID] = [:]
    private var diffViewerTabIDsByKey: [DiffKey: UUID] = [:]
    private var browserTabID: UUID?

    init(tabs: [TerminalTab] = []) {
        tabs.forEach { register($0) }
    }

    func editorTabID(filePath: String) -> UUID? {
        editorTabIDsByFilePath[filePath]
    }

    func filePreviewTabID(filePath: String) -> UUID? {
        filePreviewTabIDsByFilePath[filePath]
    }

    func externalEditorTabID(filePath: String) -> UUID? {
        externalEditorTabIDsByFilePath[filePath]
    }

    func diffViewerTabID(filePath: String, isStaged: Bool) -> UUID? {
        diffViewerTabIDsByKey[DiffKey(filePath: filePath, isStaged: isStaged)]
    }

    func existingBrowserTabID() -> UUID? {
        browserTabID
    }

    mutating func register(_ tab: TerminalTab) {
        switch tab.content {
        case let .editor(state):
            editorTabIDsByFilePath[state.filePath] = tab.id
        case let .filePreview(state):
            filePreviewTabIDsByFilePath[state.filePath] = tab.id
        case let .diffViewer(state):
            guard !state.showsAllChanges else { return }
            diffViewerTabIDsByKey[DiffKey(filePath: state.filePath, isStaged: state.isStaged)] = tab.id
        case let .terminal(pane):
            guard let filePath = pane.externalEditorFilePath else { return }
            externalEditorTabIDsByFilePath[filePath] = tab.id
        case .browser:
            browserTabID = tab.id
        case .vcs,
             .problems,
             .parentAgent,
             .codeGraph:
            return
        }
    }

    mutating func unregister(_ tab: TerminalTab) {
        switch tab.content {
        case let .editor(state):
            editorTabIDsByFilePath.removeValue(forKey: state.filePath)
        case let .filePreview(state):
            filePreviewTabIDsByFilePath.removeValue(forKey: state.filePath)
        case let .diffViewer(state):
            guard !state.showsAllChanges else { return }
            diffViewerTabIDsByKey.removeValue(forKey: DiffKey(filePath: state.filePath, isStaged: state.isStaged))
        case let .terminal(pane):
            guard let filePath = pane.externalEditorFilePath else { return }
            externalEditorTabIDsByFilePath.removeValue(forKey: filePath)
        case .browser:
            if browserTabID == tab.id {
                browserTabID = nil
            }
        case .vcs,
             .problems,
             .parentAgent,
             .codeGraph:
            return
        }
    }
}

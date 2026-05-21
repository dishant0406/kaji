import Foundation

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    let id = UUID()
    let projectPath: String
    var title: String
    let startupCommand: String?
    let injectedCommand: String?
    let agentSessionSeed: CodingAgentSessionSeed?
    let externalEditorFilePath: String?
    let searchState = TerminalSearchState()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?

    init(
        projectPath: String,
        title: String = "Terminal",
        startupCommand: String? = nil,
        injectedCommand: String? = nil,
        agentSessionSeed: CodingAgentSessionSeed? = nil,
        externalEditorFilePath: String? = nil
    ) {
        self.projectPath = projectPath
        self.title = title
        self.startupCommand = startupCommand
        self.injectedCommand = injectedCommand
        self.agentSessionSeed = agentSessionSeed
        self.externalEditorFilePath = externalEditorFilePath
    }

    deinit {
        titleDebounceTask?.cancel()
    }

    func setTitle(_ newTitle: String) {
        titleDebounceTask?.cancel()
        titleDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.title != newTitle else { return }
            self.title = newTitle
        }
    }
}

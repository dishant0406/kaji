import Foundation

enum GitCommitMessageAgentError: LocalizedError {
    case unavailable(String)
    case emptyResponse
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            message
        case .emptyResponse:
            "Kaji Agent returned an empty commit message."
        case let .failed(message):
            message
        }
    }
}

@MainActor
enum GitCommitMessageAgent {
    static var isAvailable: Bool {
        let settings = ParentAgentSettingsStore.shared
        return settings.readiness.isReady && settings.authStatus.configured
    }

    static func unavailableReason() -> String? {
        let settings = ParentAgentSettingsStore.shared
        if !settings.readiness.isReady { return settings.readiness.detail }
        if !settings.authStatus.configured { return settings.authStatus.label }
        return nil
    }

    static func generate(
        _ request: GitCommitMessageAgentRequest,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) async throws -> GitCommitMessageAgentResult {
        guard isAvailable else {
            throw GitCommitMessageAgentError.unavailable(unavailableReason() ?? "Kaji Agent is unavailable.")
        }
        return try await run(request, appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
    }

    private static func run(
        _ request: GitCommitMessageAgentRequest,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) async throws -> GitCommitMessageAgentResult {
        let store = ParentAgentTaskStore(persistence: temporaryPersistence())
        let controller = ParentAgentController(store: store)
        let box = GitCommitMessageContinuationBox(controller: controller)
        controller.process.environmentOverrides = ["KAJI_PARENT_AGENT_MODE": "kajicommit"]
        controller.process.onMessage = { message in
            controller.handle(message)
            box.handle(message)
        }
        controller.process.onError = { message in
            box.fail(message)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.continuation = continuation
                controller.submit(
                    prompt: GitCommitMessageAgentPrompt.make(request),
                    appState: appState,
                    projectStore: projectStore,
                    worktreeStore: worktreeStore
                )
            }
        } onCancel: {
            Task { @MainActor in controller.stop() }
        }
    }

    private static func temporaryPersistence() -> ParentAgentTaskPersistence {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaji-commit-agent-\(UUID().uuidString)")
            .appendingPathExtension("json")
        return ParentAgentTaskPersistence(store: CodableFileStore(fileURL: url))
    }
}

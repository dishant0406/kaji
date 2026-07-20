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
            "The commit message runtime returned an empty commit message."
        case let .failed(message):
            message
        }
    }
}

@MainActor
enum GitCommitMessageAgent {
    static var isAvailable: Bool {
        KajiAgentRuntimeLocator.resolveLaunch(
            projectPath: nil,
            approvalMode: KajiAgentPermissionMode.readAllow.rawValue,
            noSession: true,
            noLSP: true,
            noTools: true
        ).readiness.isReady
    }

    static func isAvailable(settings _: GitCommitMessageSettingsSnapshot) -> Bool {
        isAvailable
    }

    static func unavailableReason() -> String? {
        let readiness = KajiAgentRuntimeLocator.resolveLaunch(
            projectPath: nil,
            approvalMode: KajiAgentPermissionMode.readAllow.rawValue,
            noSession: true,
            noLSP: true,
            noTools: true
        ).readiness
        return readiness.isReady ? nil : readiness.detail
    }

    static func unavailableReason(settings _: GitCommitMessageSettingsSnapshot) -> String? {
        unavailableReason()
    }

    static func generate(
        _ request: GitCommitMessageAgentRequest,
        appState _: AppState,
        projectStore _: ProjectStore,
        worktreeStore _: WorktreeStore
    ) async throws -> GitCommitMessageAgentResult {
        guard isAvailable(settings: request.settings) else {
            throw GitCommitMessageAgentError.unavailable(
                unavailableReason(settings: request.settings) ?? "Commit message runtime is unavailable."
            )
        }
        return try await GitCommitMessageRuntimeClient.generate(request)
    }
}

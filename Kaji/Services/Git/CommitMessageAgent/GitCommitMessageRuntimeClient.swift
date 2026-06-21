import Foundation

@MainActor
enum GitCommitMessageRuntimeClient {
    static func generate(_ request: GitCommitMessageAgentRequest) async throws -> GitCommitMessageAgentResult {
        let process = KajiAgentProcess()
        let resolution = KajiAgentRuntimeLocator.resolveLaunch(
            projectPath: request.repoPath,
            approvalMode: KajiAgentPermissionMode.readAllow.rawValue,
            noSession: true,
            noLSP: true,
            noTools: true
        )
        guard case let .ready(launch) = resolution else {
            throw GitCommitMessageAgentError.unavailable(resolution.readiness.detail)
        }
        process.projectPath = request.repoPath
        process.approvalMode = KajiAgentPermissionMode.readAllow.rawValue
        process.launch = launch
        let frame = commandFrame(settings: request.settings, prompt: GitCommitMessageAgentPrompt.make(request))
        let box = GitCommitMessageRuntimeResponseBox(process: process, commandID: frame.id ?? UUID().uuidString)
        process.onMessage = { frame in box.handle(frame) }
        process.onError = { message in box.fail(message) }
        return try await withTaskCancellationHandler {
            let timeout = Task { @MainActor in
                try await Task.sleep(for: .seconds(120))
                box.fail(GitCommitMessageAgentError.failed("Kaji Agent timed out while generating the commit message."))
            }
            defer { timeout.cancel() }
            return try await box.run {
                process.send(frame)
            }
        } onCancel: {
            Task { @MainActor in process.stop() }
        }
    }

    static func commandFrame(settings: GitCommitMessageSettingsSnapshot, prompt: String) -> KajiAgentRPCFrame {
        KajiAgentRPCFrame(
            id: UUID().uuidString,
            type: "generate_commit_message",
            provider: settings.providerID.nilIfEmpty,
            modelId: settings.modelID.nilIfEmpty,
            promptMessage: prompt
        )
    }
}

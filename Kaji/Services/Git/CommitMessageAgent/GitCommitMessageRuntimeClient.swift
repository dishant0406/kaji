import Foundation

@MainActor
enum GitCommitMessageRuntimeClient {
    static func generate(_ request: GitCommitMessageAgentRequest) async throws -> GitCommitMessageAgentResult {
        guard let resolution = KajiCodeRuntimeLocator.resolve() else {
            throw GitCommitMessageAgentError.unavailable(KajiCodeSetupError.binaryMissing.localizedDescription)
        }
        let runner = KajiCodeCLICommandRunner()
        let prompt = GitCommitMessageAgentPrompt.make(request)
        let environment = ShellExecutionEnvironmentResolver.resolve()
        let arguments = ["-p", prompt]
        let binaryURL = resolution.binaryURL
        let result = try await Task.detached(priority: .userInitiated) {
            try runner.run(
                binaryURL: binaryURL,
                arguments: arguments,
                environment: environment,
                timeout: 120
            )
        }.value
        let message = sanitize(result.output)
        guard !message.isEmpty else {
            if result.exitCode == 0 {
                throw GitCommitMessageAgentError.emptyResponse
            }
            throw GitCommitMessageAgentError.failed("kajicode exited with code \(result.exitCode).")
        }
        return GitCommitMessageAgentResult(message: message, modelLabel: modelLabel(for: request))
    }

    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard var line = lines.last else { return "" }
        if line.hasPrefix("\""), line.hasSuffix("\""), line.count >= 2 {
            line = String(line.dropFirst().dropLast())
        }
        return line
    }

    private static func modelLabel(for request: GitCommitMessageAgentRequest) -> String? {
        let modelID = request.settings.modelID
        return modelID.isEmpty ? nil : modelID
    }
}

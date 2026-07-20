import Foundation

@MainActor
final class GitCommitMessageRuntimeResponseBox {
    private let process: KajiAgentProcess
    private let commandID: String
    private var continuation: CheckedContinuation<GitCommitMessageAgentResult, Error>?
    private var completed = false

    init(process: KajiAgentProcess, commandID: String) {
        self.process = process
        self.commandID = commandID
    }

    func run(_ action: () -> Void) async throws -> GitCommitMessageAgentResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            action()
        }
    }

    func handle(_ frame: KajiAgentRPCFrame) {
        guard !completed, frame.id == commandID, frame.type == "response" else { return }
        guard frame.success == true else {
            fail(GitCommitMessageAgentError.failed(frame.error ?? "Commit message runtime failed."))
            return
        }
        guard let message = frame.data?.objectValue?["message"]?.stringValue else {
            fail(GitCommitMessageAgentError.emptyResponse)
            return
        }
        let cleaned = clean(message)
        guard !cleaned.isEmpty else {
            fail(GitCommitMessageAgentError.emptyResponse)
            return
        }
        let modelLabel = label(from: frame.data?.objectValue?["model"])
        succeed(GitCommitMessageAgentResult(message: cleaned, modelLabel: modelLabel))
    }

    func fail(_ message: String) {
        fail(GitCommitMessageAgentError.failed(message))
    }

    func fail(_ error: Error) {
        guard !completed else { return }
        completed = true
        process.stop()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func succeed(_ result: GitCommitMessageAgentResult) {
        guard !completed else { return }
        completed = true
        process.stop()
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func label(from value: KajiAgentJSONValue?) -> String? {
        guard let object = value?.objectValue,
              let provider = object["provider"]?.stringValue,
              let id = object["id"]?.stringValue
        else { return nil }
        return "\(provider) / \(id)"
    }
}

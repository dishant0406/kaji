import Foundation

@MainActor
final class GitCommitMessageContinuationBox {
    var continuation: CheckedContinuation<GitCommitMessageAgentResult, Error>?
    private weak var controller: ParentAgentController?
    private var assistantText = ""
    private var completed = false

    init(controller: ParentAgentController) {
        self.controller = controller
    }

    func handle(_ message: ParentAgentEnvelope) {
        guard !completed else { return }
        switch message.type {
        case "assistant_delta":
            assistantText += message.message ?? ""
        case "final_response":
            succeed(finalMessage(from: message))
        case "error":
            fail(message.message ?? "Kaji Agent failed.")
        default:
            break
        }
    }

    func succeed(_ rawMessage: String) {
        let message = cleaned(rawMessage)
        guard !message.isEmpty else {
            fail(GitCommitMessageAgentError.emptyResponse)
            return
        }
        completed = true
        controller?.stop()
        continuation?.resume(returning: GitCommitMessageAgentResult(message: message))
        continuation = nil
    }

    func fail(_ message: String) {
        fail(GitCommitMessageAgentError.failed(message))
    }

    func fail(_ error: Error) {
        guard !completed else { return }
        completed = true
        controller?.stop()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func cleaned(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finalMessage(from message: ParentAgentEnvelope) -> String {
        let text = message.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text == "Parent agent turn completed.", !assistantText.isEmpty {
            return assistantText
        }
        return text.isEmpty ? assistantText : text
    }
}

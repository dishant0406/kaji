import Foundation
import Testing

@testable import Kaji

@MainActor
struct GitCommitMessageContinuationBoxTests {
    @Test
    func genericRuntimeCompletionUsesAssistantText() async throws {
        let controller = ParentAgentController(store: ParentAgentTaskStore(persistence: temporaryPersistence()))
        let box = GitCommitMessageContinuationBox(controller: controller)

        let result = try await withCheckedThrowingContinuation { continuation in
            box.continuation = continuation
            box.handle(ParentAgentEnvelope(type: "assistant_delta", message: "Improve commit flow"))
            box.handle(ParentAgentEnvelope(type: "final_response", message: "Parent agent turn completed."))
        }

        #expect(result.message == "Improve commit flow")
    }

    private func temporaryPersistence() -> ParentAgentTaskPersistence {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaji-commit-box-test-\(UUID().uuidString)")
            .appendingPathExtension("json")
        return ParentAgentTaskPersistence(store: CodableFileStore(fileURL: url))
    }
}

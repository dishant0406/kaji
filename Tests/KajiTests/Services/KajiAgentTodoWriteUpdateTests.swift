import Testing

@testable import Kaji

struct KajiAgentTodoWriteUpdateTests {
    @Test
    func ignoresNonTodoTools() {
        let update = KajiAgentTodoWriteUpdate.live(result: nil, toolName: "bash", isError: false)

        #expect(update == .notTodo)
    }

    @Test
    func parsesLivePhases() throws {
        let update = KajiAgentTodoWriteUpdate.live(
            result: KajiAgentToolResult(details: phaseDetails()),
            toolName: "todo_write",
            isError: false
        )

        guard case let .phases(phases) = update else {
            Issue.record("Expected todo phases")
            return
        }
        #expect(phases.first?.name == "Implement")
        #expect(phases.first?.tasks.first?.status == "in_progress")
    }

    @Test
    func keepsLiveFailureOutput() {
        let update = KajiAgentTodoWriteUpdate.live(
            result: KajiAgentToolResult(content: [KajiAgentContentBlock(type: "text", text: "bad json")]),
            toolName: "todo_write",
            isError: true
        )

        #expect(update == .failed("bad json"))
    }

    @Test
    func parsesRestoredFailureContent() {
        let update = KajiAgentTodoWriteUpdate.restored(object: [
            "isError": .bool(true),
            "content": .string("restore failed"),
        ], toolName: "todo_write")

        #expect(update == .failed("restore failed"))
    }

    @Test
    func reportsMissingPhases() {
        let update = KajiAgentTodoWriteUpdate.live(
            result: KajiAgentToolResult(details: .object([:])),
            toolName: "todo_write",
            isError: false
        )

        #expect(update == .missingPhases)
    }

    private func phaseDetails() -> KajiAgentJSONValue {
        .object([
            "phases": .array([
                .object([
                    "name": .string("Implement"),
                    "tasks": .array([
                        .object([
                            "content": .string("Refactor"),
                            "status": .string("in_progress"),
                        ]),
                    ]),
                ]),
            ]),
        ])
    }
}

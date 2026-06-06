import Testing

@testable import Kaji

struct KajiAgentTodoIndicatorTests {
    @Test
    func reportsOpenTodoCounts() {
        let phases = [phase(tasks: [task("Inspect", "completed"), task("Implement", "in_progress"), task("Verify", "pending")])]

        let indicator = KajiAgentTodoIndicator.active(phases: phases)

        #expect(indicator?.title == "2 todos open")
        #expect(indicator?.icon == "arrow.right.circle.fill")
        #expect(indicator?.detail == "3 total · 1 in progress · 1 completed")
    }

    @Test
    func hidesWhenAllTodosAreClosed() {
        let phases = [phase(tasks: [task("Done", "completed"), task("Skipped", "abandoned")])]

        #expect(KajiAgentTodoIndicator.active(phases: phases) == nil)
    }

    private func phase(tasks: [KajiAgentTodoItem]) -> KajiAgentTodoPhase {
        KajiAgentTodoPhase(json: .object([
            "name": .string("Build"),
            "tasks": .array(tasks.map { item in
                .object([
                    "content": .string(item.content),
                    "status": .string(item.status),
                    "notes": .array(item.notes.map { .string($0) }),
                ])
            }),
        ]))!
    }

    private func task(_ content: String, _ status: String) -> KajiAgentTodoItem {
        KajiAgentTodoItem(json: .object([
            "content": .string(content),
            "status": .string(status),
            "notes": .array([]),
        ]))!
    }
}

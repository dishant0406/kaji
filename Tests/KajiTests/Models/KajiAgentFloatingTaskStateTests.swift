import Testing

@testable import Kaji

struct KajiAgentFloatingTaskStateTests {
    @Test
    func openTodosProduceVisibleWorkAndBadgeCount() throws {
        let phase = try #require(KajiAgentTodoPhase(json: .object([
            "name": .string("Plan"),
            "tasks": .array([
                .object(["content": .string("Inspect"), "status": .string("completed")]),
                .object(["content": .string("Implement"), "status": .string("in_progress")]),
                .object(["content": .string("Verify"), "status": .string("pending")]),
            ]),
        ])))

        let state = KajiAgentFloatingTaskState(todoPhases: [phase], taskDetails: [])

        #expect(state.hasVisibleWork)
        #expect(state.isWorking)
        #expect(state.openTodoCount == 2)
        #expect(state.inProgressTodoCount == 1)
        #expect(state.badgeCount == 2)
        #expect(state.title == "2 todos open")
    }

    @Test
    func completedTodosRemainVisibleButIdle() throws {
        let phase = try #require(KajiAgentTodoPhase(json: .object([
            "name": .string("Done"),
            "tasks": .array([
                .object(["content": .string("Ship"), "status": .string("completed")]),
            ]),
        ])))

        let state = KajiAgentFloatingTaskState(todoPhases: [phase], taskDetails: [])

        #expect(state.hasVisibleWork)
        #expect(!state.isWorking)
        #expect(state.openTodoCount == 0)
        #expect(state.badgeCount == 1)
        #expect(state.title == "Tasks complete")
    }

    @Test
    func runningSubagentsProduceWorkingStateWithoutTodos() throws {
        let details = try #require(KajiAgentTaskToolDetails(json: .object([
            "progress": .array([
                .object([
                    "id": .string("agent-1"),
                    "agent": .string("codex"),
                    "status": .string("running"),
                    "task": .string("Fix scroll"),
                ]),
            ]),
        ])))

        let state = KajiAgentFloatingTaskState(todoPhases: [], taskDetails: [details])

        #expect(state.hasVisibleWork)
        #expect(state.isWorking)
        #expect(state.runningSubagentCount == 1)
        #expect(state.badgeCount == 1)
        #expect(state.title == "1 agent running")
    }

    @Test
    func failedSubagentsProduceFailureSummary() throws {
        let details = try #require(KajiAgentTaskToolDetails(json: .object([
            "results": .array([
                .object([
                    "id": .string("agent-1"),
                    "agent": .string("codex"),
                    "task": .string("Fix scroll"),
                    "exitCode": .number(1),
                ]),
            ]),
        ])))

        let state = KajiAgentFloatingTaskState(todoPhases: [], taskDetails: [details])

        #expect(state.hasVisibleWork)
        #expect(!state.isWorking)
        #expect(state.failedSubagentCount == 1)
        #expect(state.title == "1 agent failed")
        #expect(state.icon == "exclamationmark.triangle")
    }

    @Test
    func extractsTaskDetailsFromTurns() throws {
        let details = try #require(KajiAgentTaskToolDetails(json: .object([
            "progress": .array([
                .object([
                    "id": .string("agent-1"),
                    "agent": .string("codex"),
                    "status": .string("pending"),
                    "task": .string("Review"),
                ]),
            ]),
        ])))
        let tool = KajiAgentMessage(kind: .tool, title: "task", detail: "", taskDetails: details)
        var turn = KajiAgentTurn(user: nil)
        turn.blocks = [.toolGroup(KajiAgentToolGroup(tools: [tool]))]

        let state = KajiAgentFloatingTaskState(todoPhases: [], turns: [turn], isAgentRunning: false)

        #expect(state.totalSubagentCount == 1)
        #expect(state.runningSubagentCount == 1)
    }
}

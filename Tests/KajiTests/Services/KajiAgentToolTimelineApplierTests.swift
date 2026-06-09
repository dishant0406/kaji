import Testing

@testable import Kaji

struct KajiAgentToolTimelineApplierTests {
    @Test
    func startAppendsIncompleteToolToActiveGroup() throws {
        var state = State()

        KajiAgentToolTimelineApplier.start(
            event: KajiAgentSessionEvent(type: "tool_execution_start", toolCallId: "tool-1", toolName: "bash", args: .object(["cmd": .string("ls")])),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        let tool = try #require(state.tool)
        #expect(tool.title == "bash")
        #expect(tool.toolCallID == "tool-1")
        #expect(tool.isComplete == false)
        #expect(tool.toolArguments?.contains("cmd") == true)
    }

    @Test
    func startBumpsTailOnce() {
        var state = State()

        KajiAgentToolTimelineApplier.start(
            event: KajiAgentSessionEvent(type: "tool_execution_start", toolCallId: "tool-1", toolName: "bash"),
            turns: &state.turns,
            activeTurnID: &state.activeTurnID,
            tailVersion: &state.tailVersion
        )

        #expect(state.tailVersion == 1)
    }

    @Test
    func updateAppliesStreamingPreviewAndTaskDetails() throws {
        var state = State.started(toolName: "task")
        let result = KajiAgentToolResult(
            content: [.init(type: "text", text: "one\ntwo")],
            details: .object([
                "progress": .array([
                    .object(["id": .string("agent-1"), "agent": .string("codex"), "status": .string("running"), "task": .string("Fix")]),
                ]),
            ])
        )

        _ = KajiAgentToolTimelineApplier.update(
            event: KajiAgentSessionEvent(type: "tool_execution_update", toolCallId: "tool-1", toolName: "task", partialResult: result),
            turns: &state.turns,
            activeTurnID: state.activeTurnID,
            tailVersion: &state.tailVersion,
            todoPhases: &state.todoPhases
        )

        let tool = try #require(state.tool)
        #expect(tool.detail == "Streaming 2 lines")
        #expect(tool.preview == "one\ntwo")
        #expect(tool.taskDetails?.progress.first?.task == "Fix")
    }

    @Test
    func finishMarksToolCompleteAndError() throws {
        var state = State.started(toolName: "bash")

        _ = KajiAgentToolTimelineApplier.finish(
            event: KajiAgentSessionEvent(
                type: "tool_execution_end",
                toolCallId: "tool-1",
                toolName: "bash",
                result: KajiAgentToolResult(content: [.init(type: "text", text: "done")]),
                isError: true
            ),
            turns: &state.turns,
            activeTurnID: state.activeTurnID,
            tailVersion: &state.tailVersion,
            todoPhases: &state.todoPhases
        )

        let tool = try #require(state.tool)
        #expect(tool.detail == "1 line")
        #expect(tool.fullOutput == "done")
        #expect(tool.isComplete)
        #expect(tool.isError)
    }

    @Test
    func finishCapsLargeToolOutputInLiveModel() throws {
        var state = State.started(toolName: "read")
        let output = String(repeating: "x", count: 250_000)

        _ = KajiAgentToolTimelineApplier.finish(
            event: KajiAgentSessionEvent(
                type: "tool_execution_end",
                toolCallId: "tool-1",
                toolName: "read",
                result: KajiAgentToolResult(content: [.init(type: "text", text: output)])
            ),
            turns: &state.turns,
            activeTurnID: state.activeTurnID,
            tailVersion: &state.tailVersion,
            todoPhases: &state.todoPhases
        )

        let tool = try #require(state.tool)
        #expect(tool.fullOutput?.count ?? 0 < output.count)
        #expect(tool.fullOutput?.contains("truncated 50000 characters") == true)
        #expect(tool.detail == "250000 characters")
    }

    @Test
    func todoWriteUpdatesPhasesOrReturnsFailureMessage() throws {
        var state = State.started(toolName: "todo_write")
        let phases = KajiAgentToolResult(details: .object([
            "phases": .array([
                .object([
                    "name": .string("Plan"),
                    "tasks": .array([.object(["content": .string("Inspect"), "status": .string("completed")])]),
                ]),
            ]),
        ]))

        let phaseMessage = KajiAgentToolTimelineApplier.finish(
            event: KajiAgentSessionEvent(type: "tool_execution_end", toolCallId: "tool-1", toolName: "todo_write", result: phases),
            turns: &state.turns,
            activeTurnID: state.activeTurnID,
            tailVersion: &state.tailVersion,
            todoPhases: &state.todoPhases
        )

        #expect(phaseMessage == nil)
        #expect(state.todoPhases.first?.tasks.first?.content == "Inspect")

        let failedMessage = KajiAgentToolTimelineApplier.finish(
            event: KajiAgentSessionEvent(
                type: "tool_execution_end",
                toolCallId: "tool-1",
                toolName: "todo_write",
                result: KajiAgentToolResult(content: [.init(type: "text", text: "bad todo")]),
                isError: true
            ),
            turns: &state.turns,
            activeTurnID: state.activeTurnID,
            tailVersion: &state.tailVersion,
            todoPhases: &state.todoPhases
        )

        #expect(failedMessage?.title == "Todo update failed")
        #expect(failedMessage?.detail == "bad todo")
    }

    private struct State {
        var turns: [KajiAgentTurn] = []
        var activeTurnID: KajiAgentTurn.ID?
        var tailVersion = 0
        var todoPhases: [KajiAgentTodoPhase] = []

        var tool: KajiAgentMessage? {
            turns.flatMap(\.toolGroups).flatMap(\.tools).first
        }

        static func started(toolName: String) -> State {
            var state = State()
            KajiAgentToolTimelineApplier.start(
                event: KajiAgentSessionEvent(type: "tool_execution_start", toolCallId: "tool-1", toolName: toolName),
                turns: &state.turns,
                activeTurnID: &state.activeTurnID,
                tailVersion: &state.tailVersion
            )
            return state
        }
    }
}

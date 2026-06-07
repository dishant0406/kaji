import Testing

@testable import Kaji

struct KajiAgentAbortReconciliationTests {
    @Test
    func reconcileAbortedWorkStopsRunningTasksAndBumpsTailOnce() {
        var turns = [makeTurn()]
        var todoPhases = [
            KajiAgentTodoPhase(name: "Plan", tasks: [
                KajiAgentTodoItem(content: "Inspect", status: "in_progress"),
                KajiAgentTodoItem(content: "Verify", status: "pending"),
            ]),
        ]
        var tailVersion = 0

        let changed = KajiAgentTimeline.reconcileAbortedWork(
            turns: &turns,
            todoPhases: &todoPhases,
            tailVersion: &tailVersion
        )

        #expect(changed)
        #expect(tailVersion == 1)
        let tool = try! #require(turns[0].toolGroups.first?.tools.first)
        #expect(tool.isComplete)
        let details = try! #require(tool.taskDetails)
        #expect(details.progress.map(\.status) == ["aborted", "completed"])
        #expect(details.asyncState == "aborted")
        #expect(todoPhases[0].tasks.map(\.status) == ["pending", "pending"])
    }

    @Test
    func reconcileAbortedWorkPreservesFinishedAndFailedEntries() {
        var turns = [makeTurn(
            progress: [
                KajiAgentSubagentProgress(id: "done", agent: "codex", status: "completed", task: "Done"),
                KajiAgentSubagentProgress(id: "failed", agent: "codex", status: "failed", task: "Failed"),
            ],
            isComplete: true,
            asyncState: nil
        )]
        var todoPhases = [
            KajiAgentTodoPhase(name: "Plan", tasks: [
                KajiAgentTodoItem(content: "Ship", status: "completed"),
            ]),
        ]
        var tailVersion = 0

        let changed = KajiAgentTimeline.reconcileAbortedWork(
            turns: &turns,
            todoPhases: &todoPhases,
            tailVersion: &tailVersion
        )

        #expect(!changed)
        #expect(tailVersion == 0)
        let tool = try! #require(turns[0].toolGroups.first?.tools.first)
        let details = try! #require(tool.taskDetails)
        #expect(details.progress.map(\.status) == ["completed", "failed"])
        #expect(todoPhases[0].tasks.map(\.status) == ["completed"])
    }

    @Test
    func floatingStateStopsWorkingAfterAbortReconciliation() {
        var turns = [makeTurn()]
        var todoPhases = [
            KajiAgentTodoPhase(name: "Plan", tasks: [
                KajiAgentTodoItem(content: "Inspect", status: "in_progress"),
            ]),
        ]
        var tailVersion = 0

        _ = KajiAgentTimeline.reconcileAbortedWork(
            turns: &turns,
            todoPhases: &todoPhases,
            tailVersion: &tailVersion
        )
        let state = KajiAgentFloatingTaskState(todoPhases: todoPhases, turns: turns, isAgentRunning: false)

        #expect(state.hasVisibleWork)
        #expect(!state.isWorking)
        #expect(state.badgeCount == 1)
    }

    private func makeTurn(
        progress: [KajiAgentSubagentProgress] = [
            KajiAgentSubagentProgress(id: "running", agent: "codex", status: "running", task: "Inspect"),
            KajiAgentSubagentProgress(id: "done", agent: "codex", status: "completed", task: "Review"),
        ],
        isComplete: Bool = false,
        asyncState: String? = "running"
    ) -> KajiAgentTurn {
        let details = KajiAgentTaskToolDetails(progress: progress, asyncState: asyncState)
        let tool = KajiAgentMessage(
            kind: .tool,
            title: "task",
            detail: "Streaming 2 agents",
            taskDetails: details,
            isComplete: isComplete
        )
        var turn = KajiAgentTurn(user: nil)
        turn.blocks = [.toolGroup(KajiAgentToolGroup(tools: [tool]))]
        return turn
    }
}

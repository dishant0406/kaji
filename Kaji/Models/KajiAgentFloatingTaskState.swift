import Foundation

struct KajiAgentFloatingTaskState: Equatable {
    let todoPhases: [KajiAgentTodoPhase]
    let taskDetails: [KajiAgentTaskToolDetails]
    let isAgentRunning: Bool

    init(todoPhases: [KajiAgentTodoPhase], turns: [KajiAgentTurn], isAgentRunning: Bool) {
        self.todoPhases = todoPhases
        self.taskDetails = turns.flatMap(\.messages).compactMap(\.taskDetails)
        self.isAgentRunning = isAgentRunning
    }

    init(todoPhases: [KajiAgentTodoPhase], taskDetails: [KajiAgentTaskToolDetails], isAgentRunning: Bool = false) {
        self.todoPhases = todoPhases
        self.taskDetails = taskDetails
        self.isAgentRunning = isAgentRunning
    }

    var hasVisibleWork: Bool {
        totalTodoCount > 0 || !taskDetails.isEmpty
    }

    var isWorking: Bool {
        inProgressTodoCount > 0 || runningSubagentCount > 0 || hasRunningAsyncTask || (isAgentRunning && hasVisibleWork)
    }

    var badgeCount: Int {
        let activeCount = openTodoCount + runningSubagentCount
        if activeCount > 0 { return activeCount }
        return totalTodoCount + totalSubagentCount
    }

    var title: String {
        if openTodoCount > 0 && runningSubagentCount > 0 {
            return "\(openTodoCount) todo\(openTodoCount == 1 ? "" : "s") · \(runningSubagentCount) agent\(runningSubagentCount == 1 ? "" : "s")"
        }
        if openTodoCount > 0 {
            return openTodoCount == 1 ? "1 todo open" : "\(openTodoCount) todos open"
        }
        if runningSubagentCount > 0 {
            return runningSubagentCount == 1 ? "1 agent running" : "\(runningSubagentCount) agents running"
        }
        if failedSubagentCount > 0 {
            return failedSubagentCount == 1 ? "1 agent failed" : "\(failedSubagentCount) agents failed"
        }
        if totalTodoCount > 0 {
            return "Tasks complete"
        }
        return "Task activity"
    }

    var detail: String {
        [todoSummary, subagentSummary].compactMap(\.nilIfEmpty).joined(separator: " · ")
    }

    var icon: String {
        if failedSubagentCount > 0 { return "exclamationmark.triangle" }
        if isWorking { return "arrow.right.circle.fill" }
        return "checklist"
    }

    var openTodoCount: Int {
        todoItems.count { !$0.isClosed }
    }

    var inProgressTodoCount: Int {
        todoItems.count { $0.status == "in_progress" }
    }

    var totalTodoCount: Int {
        todoItems.count
    }

    var runningSubagentCount: Int {
        subagents.count { $0.isRunning }
    }

    var failedSubagentCount: Int {
        subagents.count { $0.isFailed }
    }

    var totalSubagentCount: Int {
        subagents.count
    }

    private var todoItems: [KajiAgentTodoItem] {
        todoPhases.flatMap(\.tasks)
    }

    private var subagents: [KajiAgentSubagentProgress] {
        taskDetails.flatMap(\.visibleAgents)
    }

    private var hasRunningAsyncTask: Bool {
        taskDetails.contains { detail in
            guard let state = detail.asyncState?.lowercased() else { return false }
            return ["running", "pending", "in_progress"].contains(state)
        }
    }

    private var todoSummary: String {
        guard totalTodoCount > 0 else { return "" }
        return "\(openTodoCount) open / \(totalTodoCount) todos"
    }

    private var subagentSummary: String {
        guard totalSubagentCount > 0 else { return "" }
        return "\(runningSubagentCount) running / \(totalSubagentCount) agents"
    }
}

private extension KajiAgentTodoItem {
    var isClosed: Bool {
        status == "completed" || status == "abandoned"
    }
}

private extension KajiAgentSubagentProgress {
    var isRunning: Bool {
        ["running", "pending", "in_progress"].contains(status)
    }

    var isFailed: Bool {
        ["failed", "aborted"].contains(status)
    }
}

extension KajiAgentToolTimelineApplier {
    static func applyTodoPhases(
        event: KajiAgentSessionEvent,
        result: KajiAgentToolResult?,
        source: String,
        todoPhases: inout [KajiAgentTodoPhase],
        tailVersion: inout Int
    ) -> KajiAgentMessage? {
        switch KajiAgentTodoWriteUpdate.live(result: result, toolName: event.toolName, isError: event.isError == true) {
        case .notTodo:
            return nil
        case let .failed(detail):
            KajiAgentEventLog.record("todo_write_failed", fields: ["source": .string(source)])
            return KajiAgentMessage(kind: .error, title: "Todo update failed", detail: detail)
        case .missingPhases:
            KajiAgentEventLog.record("todo_write_missing_phases", fields: ["source": .string(source)])
            return nil
        case let .phases(phases):
            todoPhases = phases
            KajiAgentTimeline.bumpTail(tailVersion: &tailVersion)
            KajiAgentEventLog.record("todo_phases_applied", fields: [
                "source": .string(source),
                "phaseCount": .number(Double(phases.count)),
                "taskCount": .number(Double(phases.flatMap(\.tasks).count)),
                "completedCount": .number(Double(phases.flatMap(\.tasks).count(where: { $0.status == "completed" }))),
                "inProgressCount": .number(Double(phases.flatMap(\.tasks).count(where: { $0.status == "in_progress" }))),
            ])
            return nil
        }
    }
}

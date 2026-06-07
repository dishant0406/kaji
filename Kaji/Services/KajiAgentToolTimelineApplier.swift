import Foundation

enum KajiAgentToolTimelineApplier {
    static func start(
        event: KajiAgentSessionEvent,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        let id = event.toolCallId ?? UUID().uuidString
        KajiAgentEventLog.record("tool_start", fields: [
            "toolName": .string(event.toolName ?? ""),
            "toolCallId": .string(id),
            "turn": .string(activeTurnID?.uuidString ?? ""),
            "lastBlock": .string(KajiAgentTimeline.activeTurnIndex(turns: turns, activeTurnID: activeTurnID)
                .flatMap { turns[$0].blocks.last?.debugName } ?? ""),
        ])
        KajiAgentTimeline.appendToolToActiveGroup(KajiAgentMessage(
            kind: .tool,
            title: event.toolName ?? "Tool",
            detail: "",
            toolCallID: id,
            toolArguments: event.args?.prettyDescription,
            isComplete: false
        ), turns: &turns, activeTurnID: &activeTurnID, tailVersion: &tailVersion)
    }

    static func update(
        event: KajiAgentSessionEvent,
        turns: inout [KajiAgentTurn],
        activeTurnID: KajiAgentTurn.ID?,
        tailVersion: inout Int,
        todoPhases: inout [KajiAgentTodoPhase]
    ) -> KajiAgentMessage? {
        guard let location = location(for: event, turns: turns, activeTurnID: activeTurnID) else { return nil }
        KajiAgentTimeline.bumpTail(tailVersion: &tailVersion)
        updateToolOutput(at: location, output: textContent(from: event.partialResult), complete: false, turns: &turns)
        updateTaskDetails(at: location, result: event.partialResult, toolName: event.toolName, turns: &turns)
        return applyTodoPhases(
            event: event,
            result: event.partialResult,
            source: "partial",
            todoPhases: &todoPhases,
            tailVersion: &tailVersion
        )
    }

    static func finish(
        event: KajiAgentSessionEvent,
        turns: inout [KajiAgentTurn],
        activeTurnID: KajiAgentTurn.ID?,
        tailVersion: inout Int,
        todoPhases: inout [KajiAgentTodoPhase]
    ) -> KajiAgentMessage? {
        guard let location = location(for: event, turns: turns, activeTurnID: activeTurnID) else { return nil }
        KajiAgentTimeline.bumpTail(tailVersion: &tailVersion)
        updateToolOutput(at: location, output: textContent(from: event.result), complete: true, turns: &turns)
        KajiAgentTimeline.updateTool(at: location, turns: &turns) { tool in
            tool.isComplete = true
            tool.isError = event.isError == true
        }
        updateTaskDetails(at: location, result: event.result, toolName: event.toolName, turns: &turns)
        return applyTodoPhases(event: event, result: event.result, source: "final", todoPhases: &todoPhases, tailVersion: &tailVersion)
    }

    private static func location(
        for event: KajiAgentSessionEvent,
        turns: [KajiAgentTurn],
        activeTurnID: KajiAgentTurn.ID?
    ) -> KajiAgentToolLocation? {
        guard let id = event.toolCallId else { return nil }
        return KajiAgentTimeline.toolLocation(turns: turns, activeTurnID: activeTurnID) { $0.toolCallID == id }
    }

    private static func updateTaskDetails(
        at location: KajiAgentToolLocation,
        result: KajiAgentToolResult?,
        toolName: String?,
        turns: inout [KajiAgentTurn]
    ) {
        guard toolName == "task", let details = KajiAgentTaskToolDetails(json: result?.details) else { return }
        KajiAgentTimeline.updateTool(at: location, turns: &turns) { tool in
            tool.taskDetails = details
        }
        KajiAgentEventLog.record("task_details_applied", fields: [
            "progressCount": .number(Double(details.progress.count)),
            "resultCount": .number(Double(details.results.count)),
            "asyncState": .string(details.asyncState ?? ""),
        ])
    }

    private static func updateToolOutput(
        at location: KajiAgentToolLocation,
        output: String?,
        complete: Bool,
        turns: inout [KajiAgentTurn]
    ) {
        guard let output, !output.isEmpty else { return }
        let preview = KajiAgentToolOutputPreview.make(
            from: output,
            toolName: KajiAgentTimeline.tool(at: location, turns: turns)?.title ?? "Tool",
            complete: complete
        )
        KajiAgentTimeline.updateTool(at: location, turns: &turns) { tool in
            tool.detail = preview.summary
            tool.preview = preview.preview
            tool.fullOutput = preview.fullOutput
            tool.truncatedLineCount = preview.truncatedLineCount
        }
    }

    private static func textContent(from result: KajiAgentToolResult?) -> String? {
        result?.content.compactMap(\.text).joined(separator: "\n")
    }
}

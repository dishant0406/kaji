extension KajiAgentTimeline {
    static func appendToolToActiveGroup(
        _ tool: KajiAgentMessage,
        turns: inout [KajiAgentTurn],
        activeTurnID: inout KajiAgentTurn.ID?,
        tailVersion: inout Int
    ) {
        bumpTail(tailVersion: &tailVersion)
        ensureActiveTurn(turns: &turns, activeTurnID: &activeTurnID)
        guard let turnIndex = activeTurnIndex(turns: turns, activeTurnID: activeTurnID) else { return }
        if let lastIndex = turns[turnIndex].blocks.indices.last,
           case var .toolGroup(group) = turns[turnIndex].blocks[lastIndex]
        {
            group.tools.append(tool)
            turns[turnIndex].blocks[lastIndex] = .toolGroup(group)
            KajiAgentEventLog.record("tool_group_append", fields: [
                "turn": .string(turns[turnIndex].id.uuidString),
                "group": .string(group.id.uuidString),
                "toolName": .string(tool.title),
                "toolCount": .number(Double(group.tools.count)),
            ])
            return
        }
        let group = KajiAgentToolGroup(tools: [tool])
        turns[turnIndex].blocks.append(.toolGroup(group))
        KajiAgentEventLog.record("tool_group_start", fields: [
            "turn": .string(turns[turnIndex].id.uuidString),
            "group": .string(group.id.uuidString),
            "toolName": .string(tool.title),
        ])
    }

    static func toolLocation(
        turns: [KajiAgentTurn],
        activeTurnID: KajiAgentTurn.ID?,
        where predicate: (KajiAgentMessage) -> Bool
    ) -> KajiAgentToolLocation? {
        if let activeIndex = activeTurnIndex(turns: turns, activeTurnID: activeTurnID),
           let location = toolLocation(in: activeIndex, turns: turns, where: predicate)
        {
            return location
        }
        for turnIndex in turns.indices.reversed() {
            if let location = toolLocation(in: turnIndex, turns: turns, where: predicate) { return location }
        }
        return nil
    }

    static func toolLocation(
        in turnIndex: Int,
        turns: [KajiAgentTurn],
        where predicate: (KajiAgentMessage) -> Bool
    ) -> KajiAgentToolLocation? {
        for blockIndex in turns[turnIndex].blocks.indices.reversed() {
            guard case let .toolGroup(group) = turns[turnIndex].blocks[blockIndex],
                  let toolIndex = group.tools.lastIndex(where: predicate)
            else { continue }
            return KajiAgentToolLocation(turn: turnIndex, block: blockIndex, tool: toolIndex)
        }
        return nil
    }

    static func tool(at location: KajiAgentToolLocation, turns: [KajiAgentTurn]) -> KajiAgentMessage? {
        guard case let .toolGroup(group) = turns[location.turn].blocks[location.block],
              group.tools.indices.contains(location.tool)
        else { return nil }
        return group.tools[location.tool]
    }

    static func updateTool(at location: KajiAgentToolLocation, turns: inout [KajiAgentTurn], mutate: (inout KajiAgentMessage) -> Void) {
        guard case var .toolGroup(group) = turns[location.turn].blocks[location.block],
              group.tools.indices.contains(location.tool)
        else { return }
        mutate(&group.tools[location.tool])
        turns[location.turn].blocks[location.block] = .toolGroup(group)
    }
}

extension KajiAgentTimeline {
    @discardableResult
    static func reconcileAbortedWork(
        turns: inout [KajiAgentTurn],
        todoPhases: inout [KajiAgentTodoPhase],
        tailVersion: inout Int
    ) -> Bool {
        var didChange = false

        for turnIndex in turns.indices {
            for blockIndex in turns[turnIndex].blocks.indices {
                guard case var .toolGroup(group) = turns[turnIndex].blocks[blockIndex] else { continue }
                var groupChanged = false
                for toolIndex in group.tools.indices {
                    var tool = group.tools[toolIndex]
                    let reconciledTaskDetails = tool.taskDetails?.reconciledForAbort()
                    if let reconciledTaskDetails, reconciledTaskDetails != tool.taskDetails {
                        tool.taskDetails = reconciledTaskDetails
                        groupChanged = true
                    }
                    if !tool.isComplete {
                        tool.isComplete = true
                        groupChanged = true
                    }
                    if groupChanged {
                        group.tools[toolIndex] = tool
                    }
                }
                if groupChanged {
                    turns[turnIndex].blocks[blockIndex] = .toolGroup(group)
                    didChange = true
                }
            }
        }

        let reconciledTodoPhases = todoPhases.reconciledForAbort()
        if reconciledTodoPhases != todoPhases {
            todoPhases = reconciledTodoPhases
            didChange = true
        }

        if didChange {
            bumpTail(tailVersion: &tailVersion)
        }

        return didChange
    }
}

private extension Array where Element == KajiAgentTodoPhase {
    func reconciledForAbort() -> [KajiAgentTodoPhase] {
        map { phase in
            KajiAgentTodoPhase(
                name: phase.name,
                tasks: phase.tasks.map { task in
                    KajiAgentTodoItem(
                        content: task.content,
                        status: task.status == "in_progress" ? "pending" : task.status,
                        notes: task.notes
                    )
                }
            )
        }
    }
}

private extension KajiAgentTaskToolDetails {
    func reconciledForAbort() -> KajiAgentTaskToolDetails {
        KajiAgentTaskToolDetails(
            progress: progress.map(\.abortedCopy),
            results: results,
            asyncState: asyncState.map { state in
                ["running", "pending", "in_progress"].contains(state.lowercased()) ? "aborted" : state
            },
            jobID: jobID
        )
    }
}

private extension KajiAgentSubagentProgress {
    var abortedCopy: KajiAgentSubagentProgress {
        KajiAgentSubagentProgress(
            id: id,
            index: index,
            agent: agent,
            status: ["running", "pending", "in_progress"].contains(status) ? "aborted" : status,
            task: task,
            assignment: assignment,
            description: description,
            currentTool: currentTool,
            currentToolArgs: currentToolArgs,
            recentOutput: recentOutput,
            failureText: failureText,
            toolCount: toolCount,
            tokens: tokens,
            durationMs: durationMs,
            cost: cost,
            sessionFile: sessionFile
        )
    }
}

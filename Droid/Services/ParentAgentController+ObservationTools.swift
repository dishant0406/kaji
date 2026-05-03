import Foundation

@MainActor
extension ParentAgentController {
    func observeAgents(_ message: ParentAgentEnvelope, toolID: String) {
        captureTerminalSnapshots(for: observedRuns(arguments: message.arguments, taskID: uuid(from: message.taskID)))
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(childRuns: observedChildRuns(arguments: message.arguments))
        ))
    }

    func waitForAgents(_ message: ParentAgentEnvelope, toolID: String) async {
        let deadline = Date().addingTimeInterval(timeout(from: message.arguments?["timeoutSeconds"]))
        var lastProgressAt = Date.distantPast
        appendWaitProgress(message: message, detail: "Waiting for child agents to finish or request attention.")
        while Date() < deadline {
            let runs = observedRuns(arguments: message.arguments, taskID: uuid(from: message.taskID))
            captureTerminalSnapshots(for: runs)
            appendWaitProgressIfNeeded(message: message, runs: runs, lastProgressAt: &lastProgressAt)
            if shouldFinishWaiting(runs: runs, taskID: uuid(from: message.taskID)) {
                process.send(ParentAgentEnvelope(
                    type: "tool_result",
                    id: toolID,
                    ok: true,
                    result: ParentAgentToolResult(message: "Child agent wait condition reached.", childRuns: childContexts(for: runs))
                ))
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        let runs = observedRuns(arguments: message.arguments, taskID: uuid(from: message.taskID))
        captureTerminalSnapshots(for: runs)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(message: "Timed out while waiting for child agents.", childRuns: childContexts(for: runs))
        ))
    }

    func sleep(_ message: ParentAgentEnvelope, toolID: String) async {
        let seconds = sleepSeconds(from: message.arguments?["seconds"])
        if let taskID = uuid(from: message.taskID) {
            let reason = message.arguments?["reason"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = if let reason, !reason.isEmpty {
                reason
            } else {
                "Waiting \(Int(seconds)) seconds before observing child agents again."
            }
            store.append(taskID: taskID, kind: .event, title: "agent.sleep", detail: detail)
        }
        try? await Task.sleep(for: .seconds(seconds))
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(message: "Slept for \(Int(seconds)) seconds.")
        ))
    }

    func observedChildRuns(arguments: [String: String]?) -> [ParentAgentChildRunContext] {
        let ids = requestedRunIDs(arguments: arguments, taskID: store.activeTaskID)
        if ids.isEmpty { return childContexts(for: Array(AgentRunStore.shared.runs.prefix(12))) }
        return ids.map { stableID in
            if let run = resolveChildRun(stableID) {
                return childContext(for: run, stableID: stableID)
            }
            return ParentAgentChildRunContext(
                id: stableID.uuidString,
                provider: "Unknown",
                project: "Unknown",
                status: "missing",
                title: "Missing child run",
                lastEvent: "No matching child run is available.",
                recentEvents: ["No matching child run is available."]
            )
        }
    }

    func observedRuns(arguments: [String: String]?, taskID: UUID?) -> [AgentRun] {
        let ids = requestedRunIDs(arguments: arguments, taskID: taskID)
        if !ids.isEmpty { return ids.compactMap(resolveChildRun) }
        return Array(AgentRunStore.shared.runs.prefix(12))
    }

    func requestedRunIDs(arguments: [String: String]?, taskID: UUID?) -> [UUID] {
        let ids = runIDs(from: arguments?["runIDs"])
        if !ids.isEmpty { return ids }
        guard let taskID,
              let task = store.tasks.first(where: { $0.id == taskID })
        else { return [] }
        return task.childRunIDs
    }

    func captureTerminalSnapshots(for runs: [AgentRun]) {
        for run in runs {
            guard let paneID = run.paneID,
                  let text = TerminalViewRegistry.shared.visibleText(for: paneID)
            else { continue }
            ChildAgentFeedStore.shared.append(runID: run.id, kind: .terminal, text: text)
        }
    }

    func appendWaitProgressIfNeeded(message: ParentAgentEnvelope, runs: [AgentRun], lastProgressAt: inout Date) {
        guard Date().timeIntervalSince(lastProgressAt) >= 6,
              let taskID = uuid(from: message.taskID),
              !runs.isEmpty
        else { return }
        lastProgressAt = Date()
        let summary = runs.map { run in
            let provider = AgentMissionControlSnapshotBuilder.providerName(for: run.providerID)
            let event = ChildAgentFeedStore.shared.recentText(runID: run.id, limit: 1).first ?? run.events.last?.text ?? run.status.rawValue
            return "\(provider): \(event)"
        }.joined(separator: "\n")
        store.append(taskID: taskID, kind: .event, title: "agent.status", detail: summary)
    }

    func appendWaitProgress(message: ParentAgentEnvelope, detail: String) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.append(taskID: taskID, kind: .event, title: "agent.wait", detail: detail)
    }
}

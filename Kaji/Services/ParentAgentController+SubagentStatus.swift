import Foundation

@MainActor
extension ParentAgentController {
    func sendSubagentStatus(_ message: ParentAgentEnvelope, toolID: String) {
        guard let taskID = uuid(from: message.taskID) else {
            sendToolError(id: toolID, message: "Parent task is unavailable.")
            return
        }
        reconcileAssignments(taskID: taskID)
        if let assignment = resolveAssignment(message, taskID: taskID) {
            captureAssignmentTerminalSnapshot(assignment)
            let updated = store.assignment(taskID: taskID, assignmentID: assignment.id) ?? assignment
            sendAssignmentResult(toolID: toolID, assignment: updated)
            return
        }
        captureAssignmentTerminalSnapshots(store.assignments(taskID: taskID))
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(assignments: assignmentContexts(taskID: taskID))
        ))
    }

    func sendSubagentResult(_ message: ParentAgentEnvelope, toolID: String) async {
        guard let taskID = uuid(from: message.taskID), let assignment = resolveAssignment(message, taskID: taskID) else {
            sendToolError(id: toolID, message: "Subagent assignment is unavailable.")
            return
        }
        reconcileAssignment(taskID: taskID, assignment: assignment)
        detectAssignmentAttention(taskID: taskID, assignment: assignment)
        await finalizeAssignmentResult(taskID: taskID, assignmentID: assignment.id)
        let updated = store.assignment(taskID: taskID, assignmentID: assignment.id) ?? assignment
        sendAssignmentResult(toolID: toolID, assignment: updated)
    }

    func waitForSubagents(_ message: ParentAgentEnvelope, toolID: String) async {
        guard let taskID = uuid(from: message.taskID) else {
            sendToolError(id: toolID, message: "Parent task is unavailable.")
            return
        }
        let deadline = Date().addingTimeInterval(timeout(from: message.arguments?["timeoutSeconds"]))
        while Date() < deadline {
            reconcileAssignments(taskID: taskID)
            let assignments = selectedAssignments(message, taskID: taskID)
            captureAssignmentTerminalSnapshots(assignments)
            if let attentionAssignment = assignments.first(where: { detectAssignmentAttention(taskID: taskID, assignment: $0) != nil }) {
                let updated = store.assignment(taskID: taskID, assignmentID: attentionAssignment.id) ?? attentionAssignment
                process.send(ParentAgentEnvelope(
                    type: "tool_result",
                    id: toolID,
                    ok: true,
                    result: ParentAgentToolResult(message: "Subagent needs attention.", assignment: assignmentContext(updated))
                ))
                return
            }
            if !assignments.isEmpty, assignments.allSatisfy(isTerminalAssignment) {
                await finalizeAssignmentResults(taskID: taskID, assignments: assignments)
                let finalized = selectedAssignments(message, taskID: taskID)
                process.send(ParentAgentEnvelope(
                    type: "tool_result",
                    id: toolID,
                    ok: true,
                    result: ParentAgentToolResult(assignments: finalized.map(assignmentContext))
                ))
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        let assignments = selectedAssignments(message, taskID: taskID)
        captureAssignmentTerminalSnapshots(assignments)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(message: "Timed out waiting for subagents.", assignments: assignments.map(assignmentContext))
        ))
    }

    func finalizeAssignmentResults(taskID: UUID, assignments: [ParentAgentAssignment]) async {
        for assignment in assignments {
            await finalizeAssignmentResult(taskID: taskID, assignmentID: assignment.id)
        }
    }

    func finalizeAssignmentResult(taskID: UUID, assignmentID: UUID) async {
        guard let assignment = store.assignment(taskID: taskID, assignmentID: assignmentID) else { return }
        captureAssignmentTerminalSnapshot(assignment)
        let run = assignment.runID.flatMap(resolveChildRun)
        let finalSummary = assignment.finalSummary
            ?? assignment.runID.flatMap { ChildAgentFeedStore.shared.finalAnswer(runID: $0) }
            ?? assignment.runID.flatMap { ChildAgentFeedStore.shared.terminalOutput(runID: $0) }
        let changedFiles = await assignmentChangedFiles(assignment: assignment, run: run)
        let status = ParentAgentAssignmentCompletionEvaluator.status(
            assignmentStatus: assignment.status,
            runStatus: run?.status,
            finalSummary: finalSummary,
            changedFiles: changedFiles
        )
        guard isTerminalStatus(status) else { return }
        store.completeAssignment(
            taskID: taskID,
            assignmentID: assignmentID,
            completion: ParentAgentAssignmentCompletion(
                summary: finalSummary,
                changedFiles: changedFiles,
                verification: run.flatMap { verificationContext(for: $0.id) } ?? assignment.verification,
                status: status
            )
        )
    }

    func assignmentChangedFiles(assignment: ParentAgentAssignment, run: AgentRun?) async -> [ParentAgentChangedFileContext] {
        if let run, !run.changedFiles.isEmpty {
            return run.changedFiles.map(changedFileContext)
        }
        if !assignment.changedFiles.isEmpty {
            return assignment.changedFiles
        }
        guard let path = assignment.worktreePath,
              let files = await AgentChangedFilesSnapshotter.snapshot(repoPath: path)
        else { return [] }
        return files.map(changedFileContext)
    }

    func isTerminalStatus(_ status: ParentAgentAssignmentStatus) -> Bool {
        switch status {
        case .completed,
             .incomplete,
             .failed,
             .stopped,
             .stale,
             .blocked,
             .requiresIsolation:
            true
        case .planned,
             .choosingAgent,
             .queued,
             .running,
             .waitingForUser:
            false
        }
    }

    func resolveAssignment(_ message: ParentAgentEnvelope, taskID: UUID) -> ParentAgentAssignment? {
        guard let rawID = message.arguments?["assignmentID"], let assignmentID = UUID(uuidString: rawID) else { return nil }
        return store.assignment(taskID: taskID, assignmentID: assignmentID)
    }

    func sendAssignmentResult(toolID: String, assignment: ParentAgentAssignment) {
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(assignment: assignmentContext(assignment))
        ))
    }

    func selectedAssignments(_ message: ParentAgentEnvelope, taskID: UUID) -> [ParentAgentAssignment] {
        if let assignment = resolveAssignment(message, taskID: taskID) {
            return [assignment]
        }
        return store.assignments(taskID: taskID)
    }

    func reconcileAssignments(taskID: UUID) {
        for assignment in store.assignments(taskID: taskID) {
            reconcileAssignment(taskID: taskID, assignment: assignment)
            detectAssignmentAttention(taskID: taskID, assignment: assignment)
        }
    }

    func reconcileAssignment(taskID: UUID, assignment: ParentAgentAssignment) {
        let run = assignment.runID.flatMap(resolveChildRun)
        let status = effectiveAssignmentStatus(assignment, run: run)
        guard status != assignment.status else { return }
        store.updateAssignmentStatus(taskID: taskID, assignmentID: assignment.id, status: status, event: status.rawValue)
    }

    func isTerminalAssignment(_ assignment: ParentAgentAssignment) -> Bool {
        switch effectiveAssignmentStatus(assignment, run: assignment.runID.flatMap(resolveChildRun)) {
        case .completed,
             .incomplete,
             .failed,
             .stopped,
             .stale,
             .blocked,
             .requiresIsolation:
            true
        case .planned,
             .choosingAgent,
             .queued,
             .running,
             .waitingForUser:
            false
        }
    }
}

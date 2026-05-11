import Foundation

@MainActor
extension ParentAgentTaskStore {
    func createAssignment(
        taskID: UUID,
        title: String,
        prompt: String,
        project: Project,
        worktree: Worktree,
        mode: ParentAgentAssignmentMode = .fresh,
        isolation: ParentAgentAssignmentIsolation = .sharedWorktree
    ) -> ParentAgentAssignment? {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        let assignment = ParentAgentAssignment(
            parentTaskID: taskID,
            title: title,
            prompt: prompt,
            project: project,
            worktree: worktree,
            mode: mode,
            isolation: isolation
        )
        tasks[index].assignments.append(assignment)
        tasks[index].updatedAt = Date()
        save()
        return assignment
    }

    func attachRun(
        taskID: UUID,
        assignmentID: UUID,
        run: ParentAgentAssignmentRunAttachment
    ) {
        updateAssignment(taskID: taskID, assignmentID: assignmentID) { assignment in
            assignment.runID = run.runID
            assignment.paneID = run.paneID
            assignment.providerID = run.providerID
            assignment.modelID = run.modelID
            assignment.status = .running
            assignment.lastEvent = "Started"
            assignment.recentEvents.append("Started")
        }
        appendChildRunIfNeeded(taskID: taskID, runID: run.runID)
    }

    func updateAssignmentStatus(
        taskID: UUID,
        assignmentID: UUID,
        status: ParentAgentAssignmentStatus,
        event: String? = nil
    ) {
        updateAssignment(taskID: taskID, assignmentID: assignmentID) { assignment in
            assignment.status = status
            if let event, !event.isEmpty {
                assignment.lastEvent = event
                assignment.recentEvents = Array((assignment.recentEvents + [event]).suffix(8))
            }
        }
    }

    func completeAssignment(
        taskID: UUID,
        assignmentID: UUID,
        completion: ParentAgentAssignmentCompletion
    ) {
        updateAssignment(taskID: taskID, assignmentID: assignmentID) { assignment in
            assignment.status = completion.status
            assignment.finalSummary = completion.summary
            assignment.changedFiles = completion.changedFiles
            assignment.verification = completion.verification
            assignment.lastEvent = completion.summary ?? completion.status.rawValue
        }
    }

    func recordAttention(taskID: UUID, assignmentID: UUID, attention: ParentAgentAttention) {
        updateAssignment(taskID: taskID, assignmentID: assignmentID) { assignment in
            assignment.status = .waitingForUser
            assignment.attention = attention
            assignment.lastEvent = "\(attention.title): \(attention.detail)"
            assignment.recentEvents = Array((assignment.recentEvents + [assignment.lastEvent ?? attention.title]).suffix(8))
        }
    }

    func clearAttention(taskID: UUID, assignmentID: UUID) {
        updateAssignment(taskID: taskID, assignmentID: assignmentID) { assignment in
            assignment.attention = nil
            if assignment.status == .waitingForUser {
                assignment.status = .running
            }
        }
    }

    func blockAssignment(
        taskID: UUID,
        assignmentID: UUID,
        status: ParentAgentAssignmentStatus,
        reason: String,
        nextAction: ParentAgentAssignmentNextAction
    ) {
        updateAssignment(taskID: taskID, assignmentID: assignmentID) { assignment in
            assignment.status = status
            assignment.blockerReason = reason
            assignment.nextAction = nextAction
            assignment.lastEvent = reason
            assignment.recentEvents = Array((assignment.recentEvents + [reason]).suffix(8))
        }
    }

    func setAssignmentIsolation(taskID: UUID, assignmentID: UUID, isolation: ParentAgentAssignmentIsolation) {
        updateAssignment(taskID: taskID, assignmentID: assignmentID) { assignment in
            assignment.isolation = isolation
            assignment.blockerReason = nil
            assignment.nextAction = .chooseAgent
            if assignment.status == .requiresIsolation {
                assignment.status = .planned
            }
        }
    }

    func assignment(taskID: UUID, assignmentID: UUID) -> ParentAgentAssignment? {
        tasks.first { $0.id == taskID }?.assignments.first { $0.id == assignmentID }
    }

    func assignments(taskID: UUID) -> [ParentAgentAssignment] {
        tasks.first { $0.id == taskID }?.assignments ?? []
    }

    private func appendChildRunIfNeeded(taskID: UUID, runID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if !tasks[index].childRunIDs.contains(runID) {
            tasks[index].childRunIDs.append(runID)
            tasks[index].updatedAt = Date()
            save()
        }
    }

    private func updateAssignment(
        taskID: UUID,
        assignmentID: UUID,
        update: (inout ParentAgentAssignment) -> Void
    ) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              let assignmentIndex = tasks[taskIndex].assignments.firstIndex(where: { $0.id == assignmentID })
        else { return }
        update(&tasks[taskIndex].assignments[assignmentIndex])
        tasks[taskIndex].assignments[assignmentIndex].updatedAt = Date()
        tasks[taskIndex].updatedAt = Date()
        save()
    }
}

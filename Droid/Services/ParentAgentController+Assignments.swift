import Foundation

@MainActor
extension ParentAgentController {
    func assignmentContext(_ assignment: ParentAgentAssignment) -> ParentAgentAssignmentContext {
        let run = assignment.runID.flatMap(resolveChildRun)
        let feed = assignment.runID.map { ChildAgentFeedStore.shared.recentText(runID: $0, limit: 5) } ?? []
        return ParentAgentAssignmentContext(
            id: assignment.id.uuidString,
            title: assignment.title,
            prompt: assignment.prompt,
            project: assignment.projectName,
            worktree: assignment.worktreeName,
            provider: assignment.providerID.map { AgentMissionControlSnapshotBuilder.providerName(for: $0) },
            model: assignment.modelID,
            runID: assignment.runID?.uuidString,
            status: effectiveAssignmentStatus(assignment, run: run).rawValue,
            mode: assignment.mode.rawValue,
            isolation: assignment.isolation.rawValue,
            lastEvent: feed.last ?? assignment.lastEvent ?? run?.events.last?.text,
            recentEvents: Array((assignment.recentEvents + feed + (run?.events.suffix(3).map(\.text) ?? [])).suffix(8)),
            finalSummary: assignment.finalSummary ?? assignment.runID.flatMap { ChildAgentFeedStore.shared.finalAnswer(runID: $0) },
            changedFiles: run?.changedFiles.map(changedFileContext) ?? assignment.changedFiles,
            verification: run.flatMap { verificationContext(for: $0.id) } ?? assignment.verification,
            attention: assignment.attention,
            blockerReason: assignment.blockerReason,
            nextAction: assignment.nextAction?.rawValue
        )
    }

    func assignmentContexts(taskID: UUID) -> [ParentAgentAssignmentContext] {
        store.assignments(taskID: taskID).map(assignmentContext)
    }

    func effectiveAssignmentStatus(_ assignment: ParentAgentAssignment, run: AgentRun?) -> ParentAgentAssignmentStatus {
        if assignment.status == .blocked || assignment.status == .requiresIsolation { return assignment.status }
        guard let run else { return assignment.runID == nil ? assignment.status : .stale }
        switch run.status {
        case .running:
            return .running
        case .waiting, .needsAttention:
            return .waitingForUser
        case .failed:
            return .failed
        case .stale:
            return .stale
        case .completed:
            return completedStatus(assignment, run: run)
        }
    }

    func completedStatus(_ assignment: ParentAgentAssignment, run: AgentRun) -> ParentAgentAssignmentStatus {
        let finalSummary = assignment.finalSummary ?? assignment.runID.flatMap { ChildAgentFeedStore.shared.finalAnswer(runID: $0) }
        let changedFiles = run.changedFiles.map(changedFileContext) + assignment.changedFiles
        return ParentAgentAssignmentCompletionEvaluator.status(
            assignmentStatus: assignment.status,
            runStatus: run.status,
            finalSummary: finalSummary,
            changedFiles: changedFiles
        )
    }
}

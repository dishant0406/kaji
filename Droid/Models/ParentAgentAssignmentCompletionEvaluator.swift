import Foundation

enum ParentAgentAssignmentCompletionEvaluator {
    static func status(
        assignmentStatus: ParentAgentAssignmentStatus,
        runStatus: AgentRunStatus?,
        finalSummary: String?,
        changedFiles: [ParentAgentChangedFileContext]
    ) -> ParentAgentAssignmentStatus {
        if assignmentStatus == .stopped { return .stopped }
        switch runStatus {
        case .running:
            return .running
        case .waiting,
             .needsAttention:
            return .waitingForUser
        case .failed:
            return .failed
        case .stale:
            return .stale
        case .completed:
            return hasMeaningfulResult(finalSummary: finalSummary, changedFiles: changedFiles) ? .completed : .incomplete
        case nil:
            return assignmentStatus == .planned ? .planned : .stale
        }
    }

    private static func hasMeaningfulResult(finalSummary: String?, changedFiles: [ParentAgentChangedFileContext]) -> Bool {
        if finalSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        return !changedFiles.isEmpty
    }
}

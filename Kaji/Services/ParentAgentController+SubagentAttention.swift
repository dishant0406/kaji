import Foundation

@MainActor
extension ParentAgentController {
    @discardableResult
    func detectAssignmentAttention(taskID: UUID, assignment: ParentAgentAssignment) -> ParentAgentAttention? {
        guard let run = assignment.runID.flatMap(resolveChildRun) else {
            clearResolvedAttention(taskID: taskID, assignment: assignment)
            return nil
        }
        guard run.status == .needsAttention,
              let event = run.events.reversed().first(where: { $0.kind == .attention })
        else {
            clearResolvedAttention(taskID: taskID, assignment: assignment)
            return nil
        }
        let attention = ParentAgentAttention(
            kind: attentionKind(label: event.label),
            providerID: run.providerID,
            title: attentionTitle(providerID: run.providerID, label: event.label),
            detail: event.text,
            suggestedAction: "Open the child agent terminal and approve, deny, or answer the request."
        )
        store.recordAttention(taskID: taskID, assignmentID: assignment.id, attention: attention)
        return attention
    }

    func clearResolvedAttention(taskID: UUID, assignment: ParentAgentAssignment) {
        guard assignment.attention != nil else { return }
        let run = assignment.runID.flatMap(resolveChildRun)
        guard effectiveAssignmentStatus(assignment, run: run) == .running else { return }
        store.clearAttention(taskID: taskID, assignmentID: assignment.id)
    }

    func attentionKind(label: String) -> ParentAgentAttentionKind {
        switch label.lowercased() {
        case "permission":
            .permission
        case "question":
            .question
        case "error",
             "blocked":
            .blocked
        default:
            .idle
        }
    }

    func attentionTitle(providerID: String, label: String) -> String {
        let provider = AgentMissionControlSnapshotBuilder.providerName(for: providerID)
        switch attentionKind(label: label) {
        case .permission:
            return "\(provider) needs permission"
        case .question:
            return "\(provider) needs input"
        case .blocked:
            return "\(provider) is blocked"
        case .idle:
            return "\(provider) needs attention"
        }
    }
}

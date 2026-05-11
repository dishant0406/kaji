import Foundation

@MainActor
extension ParentAgentController {
    func captureAssignmentTerminalSnapshot(_ assignment: ParentAgentAssignment) {
        guard let runID = assignment.runID,
              let paneID = assignment.paneID ?? resolveChildRun(runID)?.paneID,
              let text = TerminalViewRegistry.shared.visibleText(for: paneID)
        else { return }
        ChildAgentFeedStore.shared.append(runID: runID, kind: .terminal, text: text)
    }

    func captureAssignmentTerminalSnapshots(_ assignments: [ParentAgentAssignment]) {
        for assignment in assignments {
            captureAssignmentTerminalSnapshot(assignment)
        }
    }
}

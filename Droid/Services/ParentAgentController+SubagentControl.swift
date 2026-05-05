import Foundation

@MainActor
extension ParentAgentController {
    func stopSubagent(_ message: ParentAgentEnvelope, toolID: String) {
        guard let appState, let projectStore, let worktreeStore else {
            sendToolError(id: toolID, message: "Droid workspace is unavailable.")
            return
        }
        guard let taskID = uuid(from: message.taskID),
              let assignment = resolveAssignment(message, taskID: taskID),
              let runID = assignment.runID
        else {
            sendToolError(id: toolID, message: "Subagent assignment is unavailable.")
            return
        }
        let controlCenter = AgentControlCenter(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        guard let run = resolveChildRun(runID) else {
            sendToolError(id: toolID, message: "Assignment run is unavailable.")
            return
        }
        sendControlResult(controlCenter.perform(.stop(run.id)), toolID: toolID)
        store.updateAssignmentStatus(taskID: taskID, assignmentID: assignment.id, status: .stopped, event: "Stopped")
    }
}

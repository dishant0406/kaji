import Foundation

@MainActor
extension ParentAgentTaskStore {
    func load() {
        do {
            guard let snapshot = try persistence.load() else { return }
            tasks = snapshot.tasks.map(restoredTask)
            activeTaskID = tasks.contains(where: { $0.id == snapshot.activeTaskID }) ? snapshot.activeTaskID : nil
            save()
        } catch {
            tasks = []
            activeTaskID = nil
        }
    }

    func save() {
        try? persistence.save(tasks: tasks, activeTaskID: activeTaskID)
    }

    private func restoredTask(_ task: ParentAgentTask) -> ParentAgentTask {
        var task = task
        switch task.status {
        case .planning,
             .running,
             .waitingForUser:
            task.status = .stale
            task.pendingQuestion = nil
            task.pendingQuestionToolID = nil
            task.pendingQuestionOptions = []
            task.timeline.append(ParentAgentTimelineItem(
                kind: .event,
                title: "Restored",
                detail: "Kaji was restarted before this parent task finished. Start a new turn to continue."
            ))
            task.updatedAt = Date()
        case .completed,
             .failed,
             .cancelled,
             .stale:
            break
        }
        return task
    }
}

import Foundation

@MainActor
@Observable
final class ParentAgentTaskStore {
    static let shared = ParentAgentTaskStore()

    var tasks: [ParentAgentTask] = []
    var activeTaskID: UUID?

    private init() {}

    var activeTask: ParentAgentTask? {
        guard let activeTaskID else { return nil }
        return tasks.first { $0.id == activeTaskID }
    }

    var pendingQuestion: ParentAgentPendingQuestion? {
        guard let task = activeTask,
              let toolID = task.pendingQuestionToolID,
              let question = task.pendingQuestion
        else { return nil }
        return ParentAgentPendingQuestion(taskID: task.id, toolID: toolID, question: question)
    }

    func start(prompt: String) -> ParentAgentTask {
        let task = ParentAgentTask(prompt: prompt)
        tasks.append(task)
        activeTaskID = task.id
        return task
    }

    func continueActiveTask(prompt: String) -> ParentAgentTask? {
        guard let activeTaskID,
              let index = tasks.firstIndex(where: { $0.id == activeTaskID })
        else { return nil }
        tasks[index].prompt = prompt
        tasks[index].status = .running
        tasks[index].timeline.append(ParentAgentTimelineItem(kind: .user, title: "You", detail: prompt))
        tasks[index].updatedAt = Date()
        return tasks[index]
    }

    func append(taskID: UUID, kind: ParentAgentTimelineKind, title: String, detail: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].timeline.append(ParentAgentTimelineItem(kind: kind, title: title, detail: detail))
        tasks[index].updatedAt = Date()
        switch kind {
        case .final:
            tasks[index].status = .completed
        case .error:
            tasks[index].status = .failed
        case .assistant:
            tasks[index].status = .running
        case .thinking:
            tasks[index].status = .running
        case .tool,
             .event,
             .user:
            tasks[index].status = .running
        }
    }

    func appendAssistantDelta(taskID: UUID, text: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if let last = tasks[index].timeline.last, last.kind == .assistant {
            tasks[index].timeline[tasks[index].timeline.count - 1].detail += text
        } else {
            tasks[index].timeline.append(ParentAgentTimelineItem(kind: .assistant, title: "Droid", detail: text))
        }
        tasks[index].status = .running
        tasks[index].updatedAt = Date()
    }

    func appendThinkingDelta(taskID: UUID, text: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if let last = tasks[index].timeline.last, last.kind == .thinking, !last.isComplete {
            tasks[index].timeline[tasks[index].timeline.count - 1].detail += text
        } else {
            tasks[index].timeline.append(ParentAgentTimelineItem(
                kind: .thinking,
                title: "Thinking",
                detail: text,
                isComplete: false
            ))
        }
        tasks[index].status = .running
        tasks[index].updatedAt = Date()
    }

    func finishThinking(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard let itemIndex = tasks[index].timeline.lastIndex(where: { $0.kind == .thinking && !$0.isComplete }) else { return }
        tasks[index].timeline[itemIndex].isComplete = true
        tasks[index].updatedAt = Date()
    }

    func setPendingQuestion(taskID: UUID, toolID: String, question: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].pendingQuestion = question
        tasks[index].pendingQuestionToolID = toolID
        tasks[index].status = .waitingForUser
        tasks[index].timeline.append(ParentAgentTimelineItem(kind: .event, title: "Question", detail: question))
        tasks[index].updatedAt = Date()
    }

    func clearPendingQuestion(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].pendingQuestion = nil
        tasks[index].pendingQuestionToolID = nil
        tasks[index].status = .running
        tasks[index].updatedAt = Date()
    }

    func complete(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .completed
        tasks[index].updatedAt = Date()
    }

    func clearActiveTask() {
        activeTaskID = nil
    }
}

struct ParentAgentPendingQuestion: Hashable {
    let taskID: UUID
    let toolID: String
    let question: String
}

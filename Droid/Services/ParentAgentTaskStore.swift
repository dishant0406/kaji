import Foundation

@MainActor
@Observable
final class ParentAgentTaskStore {
    static let shared = ParentAgentTaskStore()

    var tasks: [ParentAgentTask] = []
    var activeTaskID: UUID?
    let persistence: ParentAgentTaskPersistence

    init(persistence: ParentAgentTaskPersistence = ParentAgentTaskPersistence()) {
        self.persistence = persistence
        load()
    }

    var activeTask: ParentAgentTask? {
        guard let activeTaskID else { return nil }
        return tasks.first { $0.id == activeTaskID }
    }

    var pendingQuestion: ParentAgentPendingQuestion? {
        guard let task = activeTask,
              let toolID = task.pendingQuestionToolID,
              let question = task.pendingQuestion
        else { return nil }
        return ParentAgentPendingQuestion(
            taskID: task.id,
            toolID: toolID,
            question: question,
            options: task.pendingQuestionOptions
        )
    }

    func start(prompt: String, attachments: [ParentAgentAttachmentContext] = []) -> ParentAgentTask {
        let task = ParentAgentTask(prompt: prompt, attachments: attachments)
        tasks.append(task)
        activeTaskID = task.id
        save()
        return task
    }

    func continueActiveTask(prompt: String, attachments: [ParentAgentAttachmentContext] = []) -> ParentAgentTask? {
        guard let activeTaskID,
              let index = tasks.firstIndex(where: { $0.id == activeTaskID })
        else { return nil }
        tasks[index].prompt = prompt
        tasks[index].status = .running
        finishStreamingAssistant(index: index)
        tasks[index].timeline.append(ParentAgentTimelineItem(kind: .user, title: "You", detail: prompt, attachments: attachments))
        tasks[index].updatedAt = Date()
        save()
        return tasks[index]
    }

    func append(
        taskID: UUID,
        kind: ParentAgentTimelineKind,
        title: String,
        detail: String,
        attachments: [ParentAgentAttachmentContext] = []
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        finishStreamingAssistant(index: index)
        tasks[index].timeline.append(ParentAgentTimelineItem(kind: kind, title: title, detail: detail, attachments: attachments))
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
        case .childRun:
            tasks[index].status = .running
        case .tool,
             .event,
             .user:
            tasks[index].status = .running
        }
        save()
    }

    func appendChildRun(taskID: UUID, runID: UUID, title: String, detail: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        finishStreamingAssistant(index: index)
        if !tasks[index].childRunIDs.contains(runID) {
            tasks[index].childRunIDs.append(runID)
        }
        tasks[index].timeline.append(ParentAgentTimelineItem(
            kind: .childRun,
            title: title,
            detail: detail,
            childRunID: runID
        ))
        tasks[index].status = .running
        tasks[index].updatedAt = Date()
        save()
    }

    func registerSpawn(taskID: UUID, fingerprint: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if !tasks[index].spawnFingerprints.contains(fingerprint) {
            tasks[index].spawnFingerprints.append(fingerprint)
        }
        tasks[index].updatedAt = Date()
        save()
    }

    func appendAssistantDelta(taskID: UUID, text: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if let last = tasks[index].timeline.last, last.kind == .assistant {
            tasks[index].timeline[tasks[index].timeline.count - 1].detail += text
            tasks[index].timeline[tasks[index].timeline.count - 1].isComplete = false
        } else {
            tasks[index].timeline.append(ParentAgentTimelineItem(kind: .assistant, title: "Droid", detail: text, isComplete: false))
        }
        tasks[index].status = .running
        tasks[index].updatedAt = Date()
        save()
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
        save()
    }

    func finishThinking(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard let itemIndex = tasks[index].timeline.lastIndex(where: { $0.kind == .thinking && !$0.isComplete }) else { return }
        tasks[index].timeline[itemIndex].isComplete = true
        tasks[index].updatedAt = Date()
        save()
    }

    func setPendingQuestion(
        taskID: UUID,
        toolID: String,
        question: String,
        options: [ParentAgentQuestionOption] = []
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].pendingQuestion = question
        tasks[index].pendingQuestionToolID = toolID
        tasks[index].pendingQuestionOptions = options
        tasks[index].status = .waitingForUser
        tasks[index].timeline.append(ParentAgentTimelineItem(kind: .event, title: "Question", detail: question))
        tasks[index].updatedAt = Date()
        save()
    }

    func clearPendingQuestion(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].pendingQuestion = nil
        tasks[index].pendingQuestionToolID = nil
        tasks[index].pendingQuestionOptions = []
        tasks[index].status = .running
        tasks[index].updatedAt = Date()
        save()
    }

    func complete(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        finishStreamingAssistant(index: index)
        tasks[index].status = .completed
        tasks[index].updatedAt = Date()
        save()
    }

    func cancelActiveTask() {
        guard let activeTaskID,
              let index = tasks.firstIndex(where: { $0.id == activeTaskID })
        else { return }
        tasks[index].status = .cancelled
        tasks[index].timeline.append(ParentAgentTimelineItem(kind: .event, title: "Stopped", detail: "Parent agent stopped."))
        tasks[index].updatedAt = Date()
        save()
    }

    func clearActiveTask() {
        activeTaskID = nil
        save()
    }

    private func finishStreamingAssistant(index: Int) {
        guard let itemIndex = tasks[index].timeline.lastIndex(where: { $0.kind == .assistant && !$0.isComplete }) else { return }
        tasks[index].timeline[itemIndex].isComplete = true
    }
}

struct ParentAgentPendingQuestion: Hashable {
    let taskID: UUID
    let toolID: String
    let question: String
    let options: [ParentAgentQuestionOption]
}

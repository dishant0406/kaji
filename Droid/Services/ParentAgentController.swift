import Foundation

@MainActor
final class ParentAgentController {
    static let shared = ParentAgentController()

    private let process = ParentAgentProcess()
    private let store = ParentAgentTaskStore.shared
    private weak var appState: AppState?
    private weak var projectStore: ProjectStore?

    private init() {
        process.onMessage = { [weak self] message in
            self?.handle(message)
        }
        process.onError = { [weak self] message in
            self?.handleError(message)
        }
    }

    func submit(prompt: String, appState: AppState, projectStore: ProjectStore) {
        self.appState = appState
        self.projectStore = projectStore
        let task = store.continueActiveTask(prompt: prompt) ?? store.start(prompt: prompt)
        process.send(ParentAgentEnvelope(
            type: "user_prompt",
            taskID: task.id.uuidString,
            prompt: prompt,
            projects: projectContexts(projectStore.projects)
        ))
    }

    var hasPendingQuestion: Bool {
        store.pendingQuestion != nil
    }

    func answerPendingQuestion(_ answer: String) {
        guard let pending = store.pendingQuestion else { return }
        store.append(taskID: pending.taskID, kind: .user, title: "You", detail: answer)
        store.clearPendingQuestion(taskID: pending.taskID)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: pending.toolID,
            ok: true,
            result: ParentAgentToolResult(answer: answer)
        ))
    }

    private func handle(_ message: ParentAgentEnvelope) {
        switch message.type {
        case "heartbeat":
            break
        case "task_event":
            append(message, kind: .event, title: message.event ?? "Agent")
        case "assistant_delta":
            appendAssistantDelta(message)
        case "thinking_delta":
            appendThinkingDelta(message)
        case "thinking_end":
            finishThinking(message)
        case "tool_call":
            append(message, kind: .tool, title: message.name ?? "Tool call")
            handleToolCall(message)
        case "final_response":
            complete(message)
        case "error":
            append(message, kind: .error, title: "Agent error")
        default:
            append(message, kind: .event, title: message.type)
        }
    }

    private func append(_ message: ParentAgentEnvelope, kind: ParentAgentTimelineKind, title: String) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.append(taskID: taskID, kind: kind, title: title, detail: message.message ?? "")
    }

    private func appendAssistantDelta(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID), let text = message.message else { return }
        store.appendAssistantDelta(taskID: taskID, text: text)
    }

    private func appendThinkingDelta(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID), let text = message.message else { return }
        store.appendThinkingDelta(taskID: taskID, text: text)
    }

    private func finishThinking(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.finishThinking(taskID: taskID)
    }

    private func complete(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.complete(taskID: taskID)
    }

    private func handleToolCall(_ message: ParentAgentEnvelope) {
        guard let id = message.id else { return }
        switch message.name {
        case "droid.list_projects":
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: true,
                result: ParentAgentToolResult(projects: projectContexts(projectStore?.projects ?? []))
            ))
        case "droid.get_active_context":
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: true,
                result: ParentAgentToolResult(activeProject: activeProjectContext())
            ))
        case "droid.ask_user":
            guard let taskID = uuid(from: message.taskID) else { return }
            let question = message.arguments?["question"] ?? message.message ?? "Droid needs your input."
            store.setPendingQuestion(taskID: taskID, toolID: id, question: question)
        default:
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: false,
                result: ParentAgentToolResult(message: "Unsupported V0 tool: \(message.name ?? "unknown")")
            ))
        }
    }

    private func handleError(_ message: String) {
        guard let taskID = store.activeTaskID else { return }
        store.append(taskID: taskID, kind: .error, title: "Agent process", detail: message)
    }

    private func activeProjectContext() -> ParentAgentProjectContext? {
        guard let appState,
              let projectStore,
              let id = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == id })
        else { return nil }
        return projectContext(project)
    }

    private func projectContexts(_ projects: [Project]) -> [ParentAgentProjectContext] {
        projects.map(projectContext)
    }

    private func projectContext(_ project: Project) -> ParentAgentProjectContext {
        ParentAgentProjectContext(id: project.id.uuidString, name: project.name, path: project.path)
    }

    private func uuid(from value: String?) -> UUID? {
        guard let value else { return nil }
        return UUID(uuidString: value)
    }
}

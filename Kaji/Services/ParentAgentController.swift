import Foundation

@MainActor
final class ParentAgentController {
    static let shared = ParentAgentController()

    let process = ParentAgentProcess()
    let store: ParentAgentTaskStore
    weak var appState: AppState?
    weak var projectStore: ProjectStore?
    weak var worktreeStore: WorktreeStore?
    var childRunLocators: [UUID: ParentAgentChildRunLocator] = [:]
    var mutationTail: Task<Void, Never>?

    init(store: ParentAgentTaskStore = .shared) {
        self.store = store
        process.onMessage = { [weak self] message in
            self?.handle(message)
        }
        process.onError = { [weak self] message in
            self?.handleError(message)
        }
    }

    func submit(
        prompt: String,
        attachments: [AskAttachment] = [],
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
        let attachmentContexts = ParentAgentAttachmentFormatter.contexts(attachments)
        let task = store.continueActiveTask(prompt: prompt, attachments: attachmentContexts)
            ?? store.start(prompt: prompt, attachments: attachmentContexts)
        process.send(ParentAgentEnvelope(
            type: "user_prompt",
            taskID: task.id.uuidString,
            prompt: prompt,
            attachments: attachmentContexts,
            projects: projectContexts(projectStore.projects)
        ))
    }

    var hasPendingQuestion: Bool {
        store.pendingQuestion != nil
    }

    func stop() {
        process.stop()
        store.cancelActiveTask()
    }

    func answerPendingQuestion(
        _ answer: String,
        displayText: String? = nil,
        attachments: [ParentAgentAttachmentContext] = []
    ) {
        guard let pending = store.pendingQuestion else { return }
        if continueAgentChoice(answer, pending: pending) {
            return
        }
        store.append(taskID: pending.taskID, kind: .user, title: "You", detail: displayText ?? answer, attachments: attachments)
        store.clearPendingQuestion(taskID: pending.taskID)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: pending.toolID,
            ok: true,
            result: ParentAgentToolResult(answer: answer)
        ))
    }

    func handle(_ message: ParentAgentEnvelope) {
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

    func handleToolCall(_ message: ParentAgentEnvelope) {
        guard let id = message.id else { return }
        switch message.name {
        case "kaji.list_projects":
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: true,
                result: ParentAgentToolResult(
                    projects: projectContexts(projectStore?.projects ?? []),
                    codingProviders: ParentAgentCodingProviderCatalog.availableProviders()
                )
            ))
        case "kaji.get_active_context":
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: true,
                result: ParentAgentToolResult(
                    activeProject: activeProjectContext(),
                    codingProviders: ParentAgentCodingProviderCatalog.availableProviders()
                )
            ))
        case "kaji.list_coding_agents":
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: true,
                result: ParentAgentToolResult(codingProviders: ParentAgentCodingProviderCatalog.availableProviders())
            ))
        case "kaji.ask_user":
            guard let taskID = uuid(from: message.taskID) else { return }
            let question = message.arguments?["question"] ?? message.message ?? "Kaji needs your input."
            store.setPendingQuestion(taskID: taskID, toolID: id, question: question)
        case "kaji.choose_agent":
            chooseAgent(message, toolID: id)
        case "kaji.subagent":
            handleSubagent(message, toolID: id)
        case "kaji.open_project",
             "kaji.select_project":
            selectProject(message, toolID: id)
        case "kaji.select_worktree":
            selectWorktree(message, toolID: id)
        case "kaji.open_terminal":
            openTerminal(message, toolID: id, split: false)
        case "kaji.open_split":
            openTerminal(message, toolID: id, split: true)
        case "kaji.spawn_agent":
            enqueueMutation { await self.spawnAgent(message, toolID: id) }
        case "kaji.send_prompt":
            enqueueMutation { await self.sendPrompt(message, toolID: id) }
        case "kaji.get_agent_status",
             "kaji.observe_agents":
            observeAgents(message, toolID: id)
        case "kaji.sleep":
            Task { await sleep(message, toolID: id) }
        case "kaji.wait_for_agents":
            Task { await waitForAgents(message, toolID: id) }
        case "kaji.jump_to_agent":
            jumpToAgent(message, toolID: id)
        case "kaji.stop_agent":
            stopAgent(message, toolID: id)
        case "kaji.resume_agent":
            resumeAgent(message, toolID: id)
        case "kaji.create_worktree":
            enqueueMutation { await self.createWorktree(message, toolID: id) }
        case "kaji.get_changed_files":
            Task { await getChangedFiles(message, toolID: id) }
        case "kaji.open_diff":
            openDiff(message, toolID: id)
        case "kaji.run_verification":
            runVerification(message, toolID: id)
        default:
            sendToolError(id: id, message: "Unsupported Kaji tool: \(message.name ?? "unknown")")
        }
    }

    func enqueueMutation(_ operation: @escaping @MainActor () async -> Void) {
        let previous = mutationTail
        let next = Task { @MainActor in
            await previous?.value
            await operation()
        }
        mutationTail = next
    }

    func append(_ message: ParentAgentEnvelope, kind: ParentAgentTimelineKind, title: String) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.append(taskID: taskID, kind: kind, title: title, detail: message.message ?? "")
    }

    func appendAssistantDelta(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID), let text = message.message else { return }
        store.appendAssistantDelta(taskID: taskID, text: text)
    }

    func appendThinkingDelta(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID), let text = message.message else { return }
        store.appendThinkingDelta(taskID: taskID, text: text)
    }

    func finishThinking(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.finishThinking(taskID: taskID)
    }

    func complete(_ message: ParentAgentEnvelope) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.complete(taskID: taskID)
    }

    func handleError(_ message: String) {
        guard let taskID = store.activeTaskID else { return }
        store.append(taskID: taskID, kind: .error, title: "Agent process", detail: message)
    }
}

import Foundation

@MainActor
final class ParentAgentController {
    static let shared = ParentAgentController()

    private let process = ParentAgentProcess()
    private let store = ParentAgentTaskStore.shared
    private weak var appState: AppState?
    private weak var projectStore: ProjectStore?
    private weak var worktreeStore: WorktreeStore?
    private var childRunLocators: [UUID: ParentAgentChildRunLocator] = [:]

    private init() {
        process.onMessage = { [weak self] message in
            self?.handle(message)
        }
        process.onError = { [weak self] message in
            self?.handleError(message)
        }
    }

    func submit(prompt: String, appState: AppState, projectStore: ProjectStore, worktreeStore: WorktreeStore) {
        self.appState = appState
        self.projectStore = projectStore
        self.worktreeStore = worktreeStore
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

    func stop() {
        process.stop()
        store.cancelActiveTask()
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
        case "droid.spawn_agent":
            Task { await spawnAgent(message, toolID: id) }
        case "droid.send_prompt":
            Task { await sendPrompt(message, toolID: id) }
        case "droid.get_agent_status":
            captureTerminalSnapshots(for: observedRuns(arguments: message.arguments, taskID: uuid(from: message.taskID)))
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: true,
                result: ParentAgentToolResult(childRuns: observedChildRuns(arguments: message.arguments))
            ))
        case "droid.observe_agents":
            captureTerminalSnapshots(for: observedRuns(arguments: message.arguments, taskID: uuid(from: message.taskID)))
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: id,
                ok: true,
                result: ParentAgentToolResult(childRuns: observedChildRuns(arguments: message.arguments))
            ))
        case "droid.sleep":
            Task { await sleep(message, toolID: id) }
        case "droid.wait_for_agents":
            Task { await waitForAgents(message, toolID: id) }
        case "droid.jump_to_agent":
            jumpToAgent(message, toolID: id)
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

    private func spawnAgent(_ message: ParentAgentEnvelope, toolID: String) async {
        guard let appState,
              let projectStore,
              let worktreeStore
        else {
            sendToolError(id: toolID, message: "Droid workspace is unavailable.")
            return
        }
        guard let project = resolveProject(message.arguments?["project"], projectStore: projectStore, appState: appState) else {
            sendToolError(id: toolID, message: "No target project is selected or matched.")
            return
        }
        worktreeStore.ensurePrimary(for: project)
        guard let worktree = worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id]) else {
            sendToolError(id: toolID, message: "No worktree is available for \(project.name).")
            return
        }
        let provider = AskProvider.resolveAnnotation(message.arguments?["provider"] ?? "") ?? .opencode
        let prompt = message.arguments?["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            sendToolError(id: toolID, message: "spawn_agent requires a prompt.")
            return
        }

        let spawnRequest = ParentAgentSpawnRequest(
            provider: provider,
            project: project,
            prompt: prompt,
            allowParallel: message.arguments?["allowParallel"] == "true"
        )
        switch ParentAgentPolicy.decideSpawn(task: parentTask(message), request: spawnRequest, runs: AgentRunStore.shared.runs) {
        case .allowed:
            break
        case let .blocked(reason, existingRunID):
            if let taskID = uuid(from: message.taskID) {
                store.append(taskID: taskID, kind: .event, title: "agent.policy", detail: reason)
            }
            let existingRun = existingRunID.flatMap(resolveChildRun)
            process.send(ParentAgentEnvelope(
                type: "tool_result",
                id: toolID,
                ok: true,
                result: ParentAgentToolResult(
                    message: reason,
                    childRun: existingRun.map { childContext(for: $0, stableID: existingRunID ?? $0.id) }
                )
            ))
            return
        }

        if let taskID = uuid(from: message.taskID) {
            store.registerSpawn(taskID: taskID, fingerprint: ParentAgentPolicy.fingerprint(for: spawnRequest))
        }

        appState.selectProject(project, worktree: worktree)
        let providerCommand = AskCommandDispatcher.startupCommand(for: provider, prompt: prompt)
        let command = AskCommandDispatcher.commandWithCompletionNotification(providerCommand, provider: provider)
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendToolError(id: toolID, message: "Provider command is unavailable.")
            return
        }
        appState.createCommandSplit(projectID: project.id, title: provider.title, command: command)

        let trackedRun = startTrackedRun(
            provider: provider,
            project: project,
            worktree: worktree,
            title: prompt,
            appState: appState
        )
        let stableRunID = trackedRun?.run.id ?? UUID()
        if let trackedRun {
            childRunLocators[stableRunID] = ParentAgentChildRunLocator(
                providerID: provider.rawValue,
                paneID: trackedRun.paneID,
                projectID: project.id,
                worktreeID: worktree.id
            )
        }
        let child = ParentAgentChildRunContext(
            id: stableRunID.uuidString,
            provider: provider.title,
            project: project.name,
            status: trackedRun?.run.status.rawValue ?? "starting",
            title: prompt,
            lastEvent: "Started in \(worktree.name)",
            recentEvents: ["Started in \(worktree.name)"]
        )
        if let taskID = uuid(from: message.taskID) {
            store.appendChildRun(taskID: taskID, runID: stableRunID, title: provider.title, detail: "Started in \(project.name)")
            ChildAgentFeedStore.shared.append(runID: stableRunID, kind: .status, text: "Started in \(project.name) / \(worktree.name)")
        }
        process.send(ParentAgentEnvelope(type: "tool_result", id: toolID, ok: true, result: ParentAgentToolResult(childRun: child)))
    }

    private func sendPrompt(_ message: ParentAgentEnvelope, toolID: String) async {
        guard let runID = UUID(uuidString: message.arguments?["runID"] ?? ""),
              let run = AgentRunStore.shared.run(id: runID),
              let paneID = run.paneID
        else {
            sendToolError(id: toolID, message: "Run is unavailable or has no live pane.")
            return
        }
        let prompt = message.arguments?["prompt"] ?? ""
        guard await TerminalCommandInjector.submit(prompt, into: paneID) else {
            sendToolError(id: toolID, message: "Could not send prompt to run.")
            return
        }
        process.send(ParentAgentEnvelope(type: "tool_result", id: toolID, ok: true, result: ParentAgentToolResult(message: "Prompt sent.")))
    }

    private func jumpToAgent(_ message: ParentAgentEnvelope, toolID: String) {
        guard let appState,
              let worktreeStore,
              let runID = UUID(uuidString: message.arguments?["runID"] ?? ""),
              let run = AgentRunStore.shared.run(id: runID),
              let paneID = run.paneID,
              let context = NotificationNavigator.resolveContext(for: paneID, appState: appState, worktreeStore: worktreeStore)
        else {
            sendToolError(id: toolID, message: "Run cannot be opened.")
            return
        }
        NotificationNavigator.navigate(to: context, appState: appState)
        process.send(ParentAgentEnvelope(type: "tool_result", id: toolID, ok: true, result: ParentAgentToolResult(message: "Opened run.")))
    }

    private func resolveProject(_ value: String?, projectStore: ProjectStore, appState: AppState) -> Project? {
        if let value, !value.isEmpty {
            let normalized = value.lowercased()
            return projectStore.projects.first { project in
                project.id.uuidString.lowercased() == normalized ||
                    project.name.lowercased() == normalized ||
                    project.path.lowercased() == normalized
            }
        }
        guard let activeProjectID = appState.activeProjectID else { return projectStore.projects.first }
        return projectStore.projects.first { $0.id == activeProjectID }
    }

    private func startTrackedRun(
        provider: AskProvider,
        project: Project,
        worktree: Worktree,
        title: String,
        appState: AppState
    ) -> ParentAgentTrackedRun? {
        guard let paneID = appState.activeTab(for: project.id)?.content.pane?.id else { return nil }
        AgentRunStore.shared.start(
            providerID: provider.rawValue,
            paneID: paneID,
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            title: title,
            confidence: .exactPane
        )
        guard let run = AgentRunStore.shared.run(providerID: provider.rawValue, paneID: paneID) else { return nil }
        return ParentAgentTrackedRun(run: run, paneID: paneID)
    }

    private func waitForAgents(_ message: ParentAgentEnvelope, toolID: String) async {
        let deadline = Date().addingTimeInterval(timeout(from: message.arguments?["timeoutSeconds"]))
        var lastProgressAt = Date.distantPast
        appendWaitProgress(message: message, detail: "Waiting for child agents to finish or request attention.")
        while Date() < deadline {
            let runs = observedRuns(arguments: message.arguments, taskID: uuid(from: message.taskID))
            captureTerminalSnapshots(for: runs)
            appendWaitProgressIfNeeded(message: message, runs: runs, lastProgressAt: &lastProgressAt)
            if shouldFinishWaiting(runs: runs, taskID: uuid(from: message.taskID)) {
                process.send(ParentAgentEnvelope(
                    type: "tool_result",
                    id: toolID,
                    ok: true,
                    result: ParentAgentToolResult(message: "Child agent wait condition reached.", childRuns: childContexts(for: runs))
                ))
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        let runs = observedRuns(arguments: message.arguments, taskID: uuid(from: message.taskID))
        captureTerminalSnapshots(for: runs)
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(message: "Timed out while waiting for child agents.", childRuns: childContexts(for: runs))
        ))
    }

    private func sleep(_ message: ParentAgentEnvelope, toolID: String) async {
        let seconds = sleepSeconds(from: message.arguments?["seconds"])
        if let taskID = uuid(from: message.taskID) {
            let reason = message.arguments?["reason"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = if let reason, !reason.isEmpty {
                reason
            } else {
                "Waiting \(Int(seconds)) seconds before observing child agents again."
            }
            store.append(taskID: taskID, kind: .event, title: "agent.sleep", detail: detail)
        }
        try? await Task.sleep(for: .seconds(seconds))
        process.send(ParentAgentEnvelope(
            type: "tool_result",
            id: toolID,
            ok: true,
            result: ParentAgentToolResult(message: "Slept for \(Int(seconds)) seconds.")
        ))
    }

    private func appendWaitProgressIfNeeded(message: ParentAgentEnvelope, runs: [AgentRun], lastProgressAt: inout Date) {
        guard Date().timeIntervalSince(lastProgressAt) >= 6,
              let taskID = uuid(from: message.taskID),
              !runs.isEmpty
        else { return }
        lastProgressAt = Date()
        let summary = runs.map { run in
            let provider = AgentMissionControlSnapshotBuilder.providerName(for: run.providerID)
            let event = ChildAgentFeedStore.shared.recentText(runID: run.id, limit: 1).first ?? run.events.last?.text ?? run.status.rawValue
            return "\(provider): \(event)"
        }.joined(separator: "\n")
        store.append(taskID: taskID, kind: .event, title: "agent.status", detail: summary)
    }

    private func appendWaitProgress(message: ParentAgentEnvelope, detail: String) {
        guard let taskID = uuid(from: message.taskID) else { return }
        store.append(taskID: taskID, kind: .event, title: "agent.wait", detail: detail)
    }

    private func observedChildRuns(arguments: [String: String]?) -> [ParentAgentChildRunContext] {
        let ids = requestedRunIDs(arguments: arguments, taskID: store.activeTaskID)
        if ids.isEmpty { return childContexts(for: Array(AgentRunStore.shared.runs.prefix(12))) }
        return ids.map { stableID in
            if let run = resolveChildRun(stableID) {
                return childContext(for: run, stableID: stableID)
            }
            return ParentAgentChildRunContext(
                id: stableID.uuidString,
                provider: "Unknown",
                project: "Unknown",
                status: "missing",
                title: "Missing child run",
                lastEvent: "No matching child run is available.",
                recentEvents: ["No matching child run is available."]
            )
        }
    }

    private func observedRuns(arguments: [String: String]?, taskID: UUID?) -> [AgentRun] {
        let ids = requestedRunIDs(arguments: arguments, taskID: taskID)
        if !ids.isEmpty { return ids.compactMap(resolveChildRun) }
        return Array(AgentRunStore.shared.runs.prefix(12))
    }

    private func requestedRunIDs(arguments: [String: String]?, taskID: UUID?) -> [UUID] {
        let ids = runIDs(from: arguments?["runIDs"])
        if !ids.isEmpty { return ids }
        guard let taskID,
              let task = store.tasks.first(where: { $0.id == taskID })
        else { return [] }
        return task.childRunIDs
    }

    private func childContexts(for runs: [AgentRun]) -> [ParentAgentChildRunContext] {
        runs.map { run in
            childContext(for: run, stableID: run.id)
        }
    }

    private func resolveChildRun(_ id: UUID) -> AgentRun? {
        if let run = AgentRunStore.shared.run(id: id) {
            return run
        }
        guard let locator = childRunLocators[id] else { return nil }
        if let run = AgentRunStore.shared.run(providerID: locator.providerID, paneID: locator.paneID) {
            return run
        }
        return AgentRunStore.shared.runs.first { run in
            run.providerID == locator.providerID &&
                run.projectID == locator.projectID &&
                run.worktreeID == locator.worktreeID
        }
    }

    private func childContext(for run: AgentRun, stableID: UUID) -> ParentAgentChildRunContext {
        let feed = ChildAgentFeedStore.shared.recentText(runID: run.id)
        let finalAnswer = ChildAgentFeedStore.shared.finalAnswer(runID: run.id)
        return ParentAgentChildRunContext(
            id: stableID.uuidString,
            provider: AgentMissionControlSnapshotBuilder.providerName(for: run.providerID),
            project: projectName(for: run.projectID),
            status: run.status.rawValue,
            title: run.title,
            lastEvent: finalAnswer ?? feed.last ?? run.events.last?.text,
            recentEvents: Array((feed + run.events.suffix(5).map(\.text)).suffix(8))
        )
    }

    private func parentTask(_ message: ParentAgentEnvelope) -> ParentAgentTask? {
        guard let taskID = uuid(from: message.taskID) else { return nil }
        return store.tasks.first { $0.id == taskID }
    }

    private func captureTerminalSnapshots(for runs: [AgentRun]) {
        for run in runs {
            guard let paneID = run.paneID,
                  let text = TerminalViewRegistry.shared.visibleText(for: paneID)
            else { continue }
            ChildAgentFeedStore.shared.append(runID: run.id, kind: .terminal, text: text)
        }
    }

    private func runIDs(from value: String?) -> [UUID] {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return value
            .split(separator: ",")
            .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func timeout(from value: String?) -> TimeInterval {
        guard let value, let parsed = TimeInterval(value) else { return 1_800 }
        return max(5, min(parsed, 600))
    }

    private func sleepSeconds(from value: String?) -> TimeInterval {
        guard let value, let parsed = TimeInterval(value) else { return 5 }
        return max(3, min(parsed, 30))
    }

    private func shouldFinishWaiting(runs: [AgentRun], taskID: UUID?) -> Bool {
        if runs.contains(where: { $0.status == .needsAttention || $0.status == .failed }) { return true }
        if !runs.isEmpty { return runs.allSatisfy(hasSettledClosedState) }
        guard let taskID,
              let task = store.tasks.first(where: { $0.id == taskID })
        else { return true }
        return task.childRunIDs.isEmpty
    }

    private func hasSettledClosedState(_ run: AgentRun) -> Bool {
        guard isClosed(run) else { return false }
        if hasMeaningfulCompletion(run) { return true }
        return Date().timeIntervalSince(run.lastEventAt) > 8
    }

    private func hasMeaningfulCompletion(_ run: AgentRun) -> Bool {
        if ChildAgentFeedStore.shared.finalAnswer(runID: run.id) != nil { return true }
        guard let event = run.events.last(where: { $0.kind == .completed || $0.kind == .transcript }) else { return false }
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        return !["started", "session completed", "turn completed"].contains(text)
    }

    private func isClosed(_ run: AgentRun) -> Bool {
        run.status == .completed || run.status == .failed || run.status == .stale
    }

    private func projectName(for id: UUID?) -> String {
        guard let id else { return "Unknown" }
        return projectStore?.projects.first { $0.id == id }?.name ?? "Unknown"
    }

    private func sendToolError(id: String, message: String) {
        process.send(ParentAgentEnvelope(type: "tool_result", id: id, ok: false, result: ParentAgentToolResult(message: message)))
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

private struct ParentAgentTrackedRun {
    let run: AgentRun
    let paneID: UUID
}

private struct ParentAgentChildRunLocator {
    let providerID: String
    let paneID: UUID
    let projectID: UUID
    let worktreeID: UUID
}

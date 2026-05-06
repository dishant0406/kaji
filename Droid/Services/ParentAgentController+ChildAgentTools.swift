import Foundation

@MainActor
extension ParentAgentController {
    func spawnAgent(_ message: ParentAgentEnvelope, toolID: String) async {
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
        guard let provider = AskProvider.resolveAnnotation(message.arguments?["provider"] ?? "") else {
            sendToolError(id: toolID, message: "spawn_agent requires a provider chosen with droid.choose_agent.")
            return
        }
        guard ParentAgentCodingProviderCatalog.availableProviders().contains(where: { $0.id == provider.rawValue }) else {
            sendToolError(id: toolID, message: "Provider \(provider.title) is not enabled and installed.")
            return
        }
        let model = message.arguments?["model"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model, !model.isEmpty else {
            sendToolError(id: toolID, message: "spawn_agent requires a model chosen with droid.choose_agent.")
            return
        }
        let prompt = message.arguments?["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            sendToolError(id: toolID, message: "spawn_agent requires a prompt.")
            return
        }

        let spawnRequest = ParentAgentSpawnRequest(
            provider: provider,
            project: project,
            prompt: prompt
        )
        switch ParentAgentPolicy.decideSpawn(task: parentTask(message), request: spawnRequest, runs: AgentRunStore.shared.runs) {
        case .allowed:
            break
        case let .blocked(reason, existingRunID):
            sendBlockedSpawnResult(message, toolID: toolID, reason: reason, existingRunID: existingRunID)
            return
        }

        if let taskID = uuid(from: message.taskID) {
            store.registerSpawn(taskID: taskID, fingerprint: ParentAgentPolicy.fingerprint(for: spawnRequest))
        }
        appState.selectProject(project, worktree: worktree)
        let providerCommand = AskCommandDispatcher.startupCommand(for: provider, prompt: prompt, model: model)
        let command = AskCommandDispatcher.commandWithCompletionNotification(providerCommand, provider: provider)
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendToolError(id: toolID, message: "Provider command is unavailable.")
            return
        }
        appState.createCommandSplit(projectID: project.id, title: provider.title, command: command)

        let title = "\(prompt) [\(model)]"
        let trackedRun = startTrackedRun(provider: provider, project: project, worktree: worktree, title: title, appState: appState)
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
            title: title,
            lastEvent: "Started in \(worktree.name)",
            recentEvents: ["Started in \(worktree.name)"],
            terminalOutput: nil
        )
        if let taskID = uuid(from: message.taskID) {
            store.appendChildRun(taskID: taskID, runID: stableRunID, title: provider.title, detail: "Started in \(project.name)")
            ChildAgentFeedStore.shared.append(runID: stableRunID, kind: .status, text: "Started in \(project.name) / \(worktree.name)")
        }
        process.send(ParentAgentEnvelope(type: "tool_result", id: toolID, ok: true, result: ParentAgentToolResult(childRun: child)))
    }

    func sendPrompt(_ message: ParentAgentEnvelope, toolID: String) async {
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

    func jumpToAgent(_ message: ParentAgentEnvelope, toolID: String) {
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

    func stopAgent(_ message: ParentAgentEnvelope, toolID: String) {
        performAgentControl(message, toolID: toolID) { controlCenter, run in
            controlCenter.perform(.stop(run.id))
        }
    }

    func resumeAgent(_ message: ParentAgentEnvelope, toolID: String) {
        performAgentControl(message, toolID: toolID) { controlCenter, run in
            controlCenter.perform(.resume(run.id))
        }
    }

    func startTrackedRun(
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
}

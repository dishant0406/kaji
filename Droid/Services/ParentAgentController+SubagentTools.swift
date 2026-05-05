import Foundation

@MainActor
extension ParentAgentController {
    func handleSubagent(_ message: ParentAgentEnvelope, toolID: String) {
        let action = message.arguments?["action"] ?? "status"
        switch action {
        case "plan", "preflight", "spawn", "send", "stop", "replace":
            enqueueMutation { await self.handleMutatingSubagent(message, toolID: toolID, action: action) }
        case "jump":
            jumpToAgent(message, toolID: toolID)
        case "status", "attention":
            sendSubagentStatus(message, toolID: toolID)
        case "result":
            Task { await self.sendSubagentResult(message, toolID: toolID) }
        case "wait":
            Task { await self.waitForSubagents(message, toolID: toolID) }
        default:
            sendToolError(id: toolID, message: "Unsupported subagent action: \(action)")
        }
    }

    func handleMutatingSubagent(_ message: ParentAgentEnvelope, toolID: String, action: String) async {
        switch action {
        case "plan":
            planSubagent(message, toolID: toolID)
        case "preflight":
            preflightSubagent(message, toolID: toolID)
        case "spawn", "replace":
            await spawnSubagent(message, toolID: toolID, mode: action == "replace" ? .replacement : .fresh)
        case "send":
            await sendSubagentPrompt(message, toolID: toolID)
        case "stop":
            stopSubagent(message, toolID: toolID)
        default:
            sendToolError(id: toolID, message: "Unsupported subagent action: \(action)")
        }
    }

    func planSubagent(_ message: ParentAgentEnvelope, toolID: String) {
        guard let taskID = uuid(from: message.taskID), let appState, let projectStore, let worktreeStore else {
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
        let prompt = message.arguments?["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            sendToolError(id: toolID, message: "subagent plan requires prompt.")
            return
        }
        if let existing = store.assignments(taskID: taskID).first(where: {
            ParentAgentAssignmentMatcher.matches(task: prompt, assignment: $0)
        }) {
            sendAssignmentResult(toolID: toolID, assignment: existing)
            return
        }
        let title = message.arguments?["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? prompt
        let isolation = ParentAgentAssignmentIsolation(rawValue: message.arguments?["isolation"] ?? "") ?? .sharedWorktree
        guard let assignment = store.createAssignment(
            taskID: taskID,
            title: title,
            prompt: prompt,
            project: project,
            worktree: worktree,
            isolation: isolation
        ) else {
            sendToolError(id: toolID, message: "Parent assignment could not be planned.")
            return
        }
        preflightAssignment(taskID: taskID, assignment: assignment)
        sendAssignmentResult(toolID: toolID, assignment: store.assignment(taskID: taskID, assignmentID: assignment.id) ?? assignment)
    }

    func preflightSubagent(_ message: ParentAgentEnvelope, toolID: String) {
        guard let taskID = uuid(from: message.taskID), let assignment = resolveAssignment(message, taskID: taskID) else {
            sendToolError(id: toolID, message: "Subagent assignment is unavailable.")
            return
        }
        preflightAssignment(taskID: taskID, assignment: assignment)
        sendAssignmentResult(toolID: toolID, assignment: store.assignment(taskID: taskID, assignmentID: assignment.id) ?? assignment)
    }

    func preflightAssignment(taskID: UUID, assignment: ParentAgentAssignment) {
        guard let projectID = assignment.projectID, let worktreeID = assignment.worktreeID else { return }
        let request = ParentAgentSubagentRequest(
            prompt: assignment.prompt,
            projectID: projectID,
            worktreeID: worktreeID,
            isolation: assignment.isolation
        )
        switch ParentAgentSubagentPolicy.decideSpawn(request: request, assignments: store.assignments(taskID: taskID)) {
        case .allowed:
            return
        case let .blocked(reason, _):
            store.blockAssignment(taskID: taskID, assignmentID: assignment.id, status: .blocked, reason: reason, nextAction: .waitForAssignment)
        case let .requiresIsolation(reason, _):
            store.blockAssignment(
                taskID: taskID,
                assignmentID: assignment.id,
                status: .requiresIsolation,
                reason: reason,
                nextAction: .useIsolatedWorktree
            )
        }
    }

    func spawnSubagent(_ message: ParentAgentEnvelope, toolID: String, mode: ParentAgentAssignmentMode) async {
        guard let taskID = uuid(from: message.taskID), let appState, let projectStore, let worktreeStore else {
            sendToolError(id: toolID, message: "Droid workspace is unavailable.")
            return
        }
        let previousAssignment = resolveAssignment(message, taskID: taskID)
        if let previousAssignment, previousAssignment.status == .waitingForUser || previousAssignment.status == .running {
            sendToolError(
                id: toolID,
                message: "Assignment is active or waiting for user approval. Use send/status/jump instead of spawning."
            )
            return
        }
        let projectValue = message.arguments?["project"] ?? previousAssignment?.projectName ?? previousAssignment?.projectID?.uuidString
        guard let project = resolveProject(projectValue, projectStore: projectStore, appState: appState) else {
            sendToolError(id: toolID, message: "No target project is selected or matched.")
            return
        }
        worktreeStore.ensurePrimary(for: project)
        let preferredWorktreeID = previousAssignment?.worktreeID ?? appState.activeWorktreeID[project.id]
        guard var worktree = worktreeStore.preferred(for: project.id, matching: preferredWorktreeID) else {
            sendToolError(id: toolID, message: "No worktree is available for \(project.name).")
            return
        }
        guard let provider = AskProvider.resolveAnnotation(message.arguments?["provider"] ?? "") else {
            sendToolError(id: toolID, message: "subagent spawn requires provider from droid.choose_agent.")
            return
        }
        let model = message.arguments?["model"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model, !model.isEmpty else {
            sendToolError(id: toolID, message: "subagent spawn requires model from droid.choose_agent.")
            return
        }
        let prompt = message.arguments?["prompt"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? previousAssignment?.prompt ?? ""
        guard !prompt.isEmpty else {
            sendToolError(id: toolID, message: "subagent spawn requires prompt.")
            return
        }

        let title = message.arguments?["title"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? previousAssignment?.title ?? prompt
        let isolation = ParentAgentAssignmentIsolation(rawValue: message.arguments?["isolation"] ?? "")
            ?? previousAssignment?.isolation
            ?? .sharedWorktree
        if isolation == .isolatedWorktree {
            guard let isolated = await createIsolatedSubagentWorktree(title: title, project: project, worktreeStore: worktreeStore) else {
                sendToolError(id: toolID, message: "Could not create an isolated worktree for \(title).")
                return
            }
            worktree = isolated
        }
        let subagentRequest = ParentAgentSubagentRequest(
            prompt: prompt,
            projectID: project.id,
            worktreeID: worktree.id,
            isolation: isolation
        )
        let decision = ParentAgentSubagentPolicy.decideSpawn(
            request: subagentRequest,
            assignments: store.assignments(taskID: taskID)
        )
        switch decision {
        case .allowed:
            break
        case let .blocked(reason, assignmentID):
            let suffix = assignmentID.map { " assignmentID=\($0.uuidString)" } ?? ""
            sendToolError(id: toolID, message: reason + suffix)
            return
        case let .requiresIsolation(reason, assignmentID):
            let suffix = assignmentID.map { " assignmentID=\($0.uuidString)" } ?? ""
            sendToolError(id: toolID, message: reason + suffix)
            return
        }
        let spawnRequest = ParentAgentSpawnRequest(provider: provider, project: project, prompt: prompt)
        switch ParentAgentPolicy.decideSpawn(task: parentTask(message), request: spawnRequest, runs: AgentRunStore.shared.runs) {
        case .allowed:
            break
        case let .blocked(reason, existingRunID):
            sendBlockedSpawnResult(message, toolID: toolID, reason: reason, existingRunID: existingRunID)
            return
        }
        guard let assignment = store.createAssignment(
            taskID: taskID,
            title: title,
            prompt: prompt,
            project: project,
            worktree: worktree,
            mode: mode,
            isolation: isolation
        ) else {
            sendToolError(id: toolID, message: "Parent assignment could not be created.")
            return
        }
        store.registerSpawn(taskID: taskID, fingerprint: ParentAgentPolicy.fingerprint(for: spawnRequest))

        appState.selectProject(project, worktree: worktree)
        let providerCommand = AskCommandDispatcher.startupCommand(for: provider, prompt: prompt, model: model)
        let command = AskCommandDispatcher.commandWithCompletionNotification(providerCommand, provider: provider)
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.updateAssignmentStatus(taskID: taskID, assignmentID: assignment.id, status: .failed, event: "Provider command unavailable")
            sendToolError(id: toolID, message: "Provider command is unavailable.")
            return
        }
        appState.createCommandSplit(projectID: project.id, title: provider.title, command: command)
        let trackedRun = startTrackedRun(
            provider: provider,
            project: project,
            worktree: worktree,
            title: "\(title) [\(model)]",
            appState: appState
        )
        let runID = trackedRun?.run.id ?? UUID()
        if let trackedRun {
            childRunLocators[runID] = ParentAgentChildRunLocator(
                providerID: provider.rawValue,
                paneID: trackedRun.paneID,
                projectID: project.id,
                worktreeID: worktree.id
            )
        }
        store.attachRun(
            taskID: taskID,
            assignmentID: assignment.id,
            run: ParentAgentAssignmentRunAttachment(
                runID: runID,
                paneID: trackedRun?.paneID,
                providerID: provider.rawValue,
                modelID: model
            )
        )
        store.appendChildRun(taskID: taskID, runID: runID, title: provider.title, detail: "Started \(title) in \(project.name)")
        ChildAgentFeedStore.shared.append(
            runID: runID,
            kind: .status,
            text: "Started \(title) in \(project.name) / \(worktree.name)"
        )
        let updated = store.assignment(taskID: taskID, assignmentID: assignment.id) ?? assignment
        sendAssignmentResult(toolID: toolID, assignment: updated)
    }

    func sendSubagentPrompt(_ message: ParentAgentEnvelope, toolID: String) async {
        guard let taskID = uuid(from: message.taskID), let assignment = resolveAssignment(message, taskID: taskID) else {
            sendToolError(id: toolID, message: "Subagent assignment is unavailable.")
            return
        }
        guard let runID = assignment.runID, let run = resolveChildRun(runID), let paneID = run.paneID else {
            sendToolError(id: toolID, message: "Assignment has no live pane. Start a replacement run instead.")
            return
        }
        let prompt = message.arguments?["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            sendToolError(id: toolID, message: "subagent send requires prompt.")
            return
        }
        guard await TerminalCommandInjector.submit(prompt, into: paneID) else {
            sendToolError(id: toolID, message: "Could not send prompt to assignment run.")
            return
        }
        store.updateAssignmentStatus(taskID: taskID, assignmentID: assignment.id, status: .running, event: "Prompt sent")
        sendAssignmentResult(toolID: toolID, assignment: store.assignment(taskID: taskID, assignmentID: assignment.id) ?? assignment)
    }
}

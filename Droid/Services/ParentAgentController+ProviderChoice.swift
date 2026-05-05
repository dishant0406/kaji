import Foundation

@MainActor
extension ParentAgentController {
    func chooseAgent(_ message: ParentAgentEnvelope, toolID: String) {
        guard let taskID = uuid(from: message.taskID) else { return }
        let task = message.arguments?["task"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "this task"
        let project = message.arguments?["project"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignmentID = uuid(from: message.arguments?["assignmentID"])
        reconcileAssignments(taskID: taskID)
        let options = providerChoiceOptions(project: project, task: task, taskID: taskID, assignmentID: assignmentID)
        guard !options.isEmpty else {
            sendToolError(id: toolID, message: "No enabled and installed coding agents are available.")
            return
        }
        let question = providerChoiceQuestion(project: project, task: task)
        store.setPendingQuestion(taskID: taskID, toolID: toolID, question: question, options: options)
    }

    func continueAgentChoice(_ answer: String, pending: ParentAgentPendingQuestion) -> Bool {
        let fields = choiceFields(answer)
        guard fields["stage"] == "provider",
              let providerID = fields["provider"],
              let provider = AskProvider.resolveAnnotation(providerID)
        else { return false }
        let project = fields["project"]
        let mode = fields["mode"]
        let assignmentID = fields["assignmentID"]
        if mode == "isolate", let assignmentID = assignmentID.flatMap(UUID.init(uuidString:)) {
            store.setAssignmentIsolation(
                taskID: pending.taskID,
                assignmentID: assignmentID,
                isolation: .isolatedWorktree
            )
            store.clearPendingQuestion(taskID: pending.taskID)
            return true
        }
        let projectPath = projectPath(for: project)
        let models = ParentAgentCodingProviderCatalog.modelOptions(for: provider, projectPath: projectPath)
        guard !models.isEmpty else {
            sendToolError(id: pending.toolID, message: "No models are available for \(provider.title).")
            store.clearPendingQuestion(taskID: pending.taskID)
            return true
        }
        let options = models.map { model in
            let value = providerChoiceValue(
                project: project,
                providerID: provider.rawValue,
                model: model,
                mode: mode,
                assignmentID: assignmentID
            )
            return ParentAgentQuestionOption(
                id: "\(provider.rawValue)-\(model)",
                title: model,
                detail: provider.title,
                value: value
            )
        }
        store.setPendingQuestion(
            taskID: pending.taskID,
            toolID: pending.toolID,
            question: modelChoiceQuestion(project: project, provider: provider),
            options: options
        )
        return true
    }

    func providerChoiceOptions(
        project: String?,
        task: String,
        taskID: UUID? = nil,
        assignmentID: UUID? = nil
    ) -> [ParentAgentQuestionOption] {
        let projectPath = projectPath(for: project)
        let providers = ParentAgentCodingProviderCatalog.availableProviders().map { provider in
            let defaultModel = CodingAgentRegistry.shared.agent(id: provider.id)?.defaultModel(projectPath: projectPath)
            let value = providerStageValue(project: project, providerID: provider.id, mode: "new", assignmentID: nil)
            return ParentAgentQuestionOption(
                id: provider.id,
                title: provider.title,
                detail: defaultModel.map { "Default: \($0)" } ?? "Choose a model next",
                value: value
            )
        }
        if let taskID, let assignmentID, let assignment = store.assignment(taskID: taskID, assignmentID: assignmentID) {
            return choices(for: assignment, providers: providers, project: project)
        }
        let assignmentOptions = assignmentChoiceOptions(project: project, task: task, taskID: taskID)
        if !assignmentOptions.isEmpty { return assignmentOptions }
        return providers
    }

    private func choices(
        for assignment: ParentAgentAssignment,
        providers: [ParentAgentQuestionOption],
        project: String?
    ) -> [ParentAgentQuestionOption] {
        if assignment.status.canContinue {
            return [
                ParentAgentQuestionOption(
                    id: "continue-\(assignment.id.uuidString)",
                    title: "Continue: \(assignment.title)",
                    detail: assignmentChoiceDetail(assignment),
                    value: continuationChoiceValue(project: project, assignment: assignment),
                ),
            ]
        }
        if assignment.status == .requiresIsolation {
            return [
                ParentAgentQuestionOption(
                    id: "isolate-\(assignment.id.uuidString)",
                    title: "Use isolated worktree: \(assignment.title)",
                    detail: assignment.blockerReason,
                    value: isolationChoiceValue(project: project, assignment: assignment),
                ),
            ]
        }
        if assignment.status.canReplace || assignment.status == .planned || assignment.status == .blocked {
            return providers.map { provider in
                ParentAgentQuestionOption(
                    id: "assignment-\(assignment.id.uuidString)-\(provider.id)",
                    title: provider.title,
                    detail: provider.detail,
                    value: providerStageValue(
                        project: project,
                        providerID: provider.id,
                        mode: "new",
                        assignmentID: assignment.id.uuidString
                    )
                )
            }
        }
        return []
    }

    private func assignmentChoiceOptions(project: String?, task: String, taskID: UUID?) -> [ParentAgentQuestionOption] {
        guard let taskID,
              let parentTask = store.tasks.first(where: { $0.id == taskID })
        else { return [] }
        let assignments = parentTask.assignments.filter { assignment in
            guard let project else { return true }
            return assignment.projectName == project || assignment.projectID?.uuidString == project
        }.filter { assignment in
            ParentAgentAssignmentMatcher.matches(task: task, assignment: assignment)
        }
        let continuations = assignments.filter { assignment in
            assignment.status.canContinue && assignment.runID.flatMap(resolveChildRun)?.paneID != nil
        }.map { assignment in
            ParentAgentQuestionOption(
                id: "continue-\(assignment.id.uuidString)",
                title: "Continue: \(assignment.title)",
                detail: assignmentChoiceDetail(assignment),
                value: continuationChoiceValue(project: project, assignment: assignment)
            )
        }
        let replacements = assignments.filter(\.status.canReplace).flatMap { assignment in
            ParentAgentCodingProviderCatalog.availableProviders().map { provider in
                let value = providerStageValue(
                    project: project,
                    providerID: provider.id,
                    mode: "replacement",
                    assignmentID: assignment.id.uuidString
                )
                return ParentAgentQuestionOption(
                    id: "replace-\(assignment.id.uuidString)-\(provider.id)",
                    title: "Replace: \(assignment.title) with \(provider.title)",
                    detail: assignmentChoiceDetail(assignment),
                    value: value
                )
            }
        }
        return continuations + replacements
    }

    private func assignmentChoiceDetail(_ assignment: ParentAgentAssignment) -> String {
        let provider = assignment.providerID.map { AgentMissionControlSnapshotBuilder.providerName(for: $0) } ?? "Agent"
        let run = assignment.runID.map { String($0.uuidString.prefix(8)) } ?? "no run"
        let worktree = assignment.worktreeName ?? "worktree"
        return "\(provider) - \(assignment.status.rawValue) - \(worktree) - \(run)"
    }

    private func continuationChoiceValue(project: String?, assignment: ParentAgentAssignment) -> String {
        [
            "mode=continue",
            "assignmentID=\(assignment.id.uuidString)",
            assignment.runID.map { "runID=\($0.uuidString)" },
            project.map { "project=\($0)" },
        ].compactMap(\.self).joined(separator: "\n")
    }

    private func isolationChoiceValue(project: String?, assignment: ParentAgentAssignment) -> String {
        [
            "mode=isolate",
            "assignmentID=\(assignment.id.uuidString)",
            "isolation=\(ParentAgentAssignmentIsolation.isolatedWorktree.rawValue)",
            project.map { "project=\($0)" },
        ].compactMap(\.self).joined(separator: "\n")
    }

    private func providerStageValue(project: String?, providerID: String, mode: String?, assignmentID: String?) -> String {
        [
            "stage=provider",
            mode.map { "mode=\($0)" },
            assignmentID.map { "assignmentID=\($0)" },
            "provider=\(providerID)",
            project.map { "project=\($0)" },
        ].compactMap(\.self).joined(separator: "\n")
    }

    private func providerChoiceValue(project: String?, providerID: String, model: String, mode: String?, assignmentID: String?) -> String {
        [
            mode.map { "mode=\($0)" },
            assignmentID.map { "assignmentID=\($0)" },
            "provider=\(providerID)",
            "model=\(model)",
            project.map { "project=\($0)" },
        ].compactMap(\.self).joined(separator: "\n")
    }

    private func legacyContinuationChoiceOptions(project: String?, task: ParentAgentTask) -> [ParentAgentQuestionOption] {
        let assignedRunIDs = Set(task.assignments.compactMap(\.runID))
        let runs = task.childRunIDs.filter { !assignedRunIDs.contains($0) }.compactMap(resolveChildRun).filter { run in
            guard run.paneID != nil else { return false }
            guard let project else { return true }
            return projectName(for: run.projectID) == project || run.projectID?.uuidString == project
        }
        return runs.map { run in
            ParentAgentQuestionOption(
                id: "continue-legacy-\(run.id.uuidString)",
                title: "Continue legacy run: \(AgentMissionControlSnapshotBuilder.providerName(for: run.providerID))",
                detail: "\(run.status.rawValue) - \(run.title) - \(String(run.id.uuidString.prefix(8)))",
                value: legacyContinuationChoiceValue(project: project, runID: run.id)
            )
        }
    }

    private func providerChoiceQuestion(project: String?, task: String) -> String {
        if let project, !project.isEmpty {
            return "Choose a coding agent for `\(project)`: \(task)"
        }
        return "Choose a coding agent for: \(task)"
    }

    private func modelChoiceQuestion(project: String?, provider: AskProvider) -> String {
        if let project, !project.isEmpty {
            return "Choose a \(provider.title) model for `\(project)`"
        }
        return "Choose a \(provider.title) model"
    }

    private func projectPath(for project: String?) -> String? {
        guard let projectStore, let appState else { return nil }
        return resolveProject(project, projectStore: projectStore, appState: appState)?.path
    }

    private func legacyContinuationChoiceValue(project: String?, runID: UUID) -> String {
        [
            "mode=continue",
            "runID=\(runID.uuidString)",
            project.map { "project=\($0)" },
        ].compactMap(\.self).joined(separator: "\n")
    }

    private func choiceFields(_ value: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: value.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
    }
}

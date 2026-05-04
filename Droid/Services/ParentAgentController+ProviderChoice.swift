import Foundation

@MainActor
extension ParentAgentController {
    func chooseAgent(_ message: ParentAgentEnvelope, toolID: String) {
        guard let taskID = uuid(from: message.taskID) else { return }
        let task = message.arguments?["task"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "this task"
        let project = message.arguments?["project"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = providerChoiceOptions(project: project, taskID: taskID)
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
        let projectPath = projectPath(for: project)
        let models = ParentAgentCodingProviderCatalog.modelOptions(for: provider, projectPath: projectPath)
        guard !models.isEmpty else {
            sendToolError(id: pending.toolID, message: "No models are available for \(provider.title).")
            store.clearPendingQuestion(taskID: pending.taskID)
            return true
        }
        let options = models.map { model in
            ParentAgentQuestionOption(
                id: "\(provider.rawValue)-\(model)",
                title: model,
                detail: provider.title,
                value: providerChoiceValue(project: project, providerID: provider.rawValue, model: model)
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

    func providerChoiceOptions(project: String?, taskID: UUID? = nil) -> [ParentAgentQuestionOption] {
        let projectPath = projectPath(for: project)
        let providers = ParentAgentCodingProviderCatalog.availableProviders().map { provider in
            let defaultModel = CodingAgentRegistry.shared.agent(id: provider.id)?.defaultModel(projectPath: projectPath)
            return ParentAgentQuestionOption(
                id: provider.id,
                title: provider.title,
                detail: defaultModel.map { "Default: \($0)" } ?? "Choose a model next",
                value: providerStageValue(project: project, providerID: provider.id)
            )
        }
        return continuationOptions(project: project, taskID: taskID) + providers
    }

    private func continuationOptions(project: String?, taskID: UUID?) -> [ParentAgentQuestionOption] {
        guard let taskID,
              let task = store.tasks.first(where: { $0.id == taskID })
        else { return [] }
        let runs = task.childRunIDs.compactMap(resolveChildRun).filter { run in
            guard run.paneID != nil else { return false }
            guard let project else { return true }
            return projectName(for: run.projectID) == project || run.projectID?.uuidString == project
        }
        return runs.map { run in
            ParentAgentQuestionOption(
                id: "continue-\(run.id.uuidString)",
                title: "Continue in \(AgentMissionControlSnapshotBuilder.providerName(for: run.providerID))",
                detail: "\(run.status.rawValue) · \(run.title)",
                value: continuationChoiceValue(project: project, runID: run.id)
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

    private func providerStageValue(project: String?, providerID: String) -> String {
        [
            "stage=provider",
            "provider=\(providerID)",
            project.map { "project=\($0)" },
        ].compactMap(\.self).joined(separator: "\n")
    }

    private func providerChoiceValue(project: String?, providerID: String, model: String) -> String {
        [
            "provider=\(providerID)",
            "model=\(model)",
            project.map { "project=\($0)" },
        ].compactMap(\.self).joined(separator: "\n")
    }

    private func continuationChoiceValue(project: String?, runID: UUID) -> String {
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

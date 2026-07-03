import Foundation

enum AgentEditServiceError: LocalizedError {
    case missingProvider
    case missingCommand
    case emptySelection
    case emptyResponse
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProvider:
            "Choose an AI provider before generating an edit."
        case .missingCommand:
            "The selected provider does not expose a command for inline edits."
        case .emptySelection:
            "Select code before using Inline Edit."
        case .emptyResponse:
            "The provider returned an empty edit."
        case let .commandFailed(message):
            message.isEmpty ? "Inline edit generation failed." : message
        }
    }
}

@MainActor
protocol AgentEditProviding {
    func generateEdit(request: AgentEditRequest) async throws -> AgentEditResponse
}

struct AgentEditService: AgentEditProviding {
    func generateEdit(request: AgentEditRequest) async throws -> AgentEditResponse {
        guard !request.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentEditServiceError.emptySelection
        }
        guard request.provider != .terminal else {
            throw AgentEditServiceError.missingProvider
        }
        guard let agent = CodingAgentRegistry.shared.agent(id: request.provider.rawValue) else {
            throw AgentEditServiceError.missingProvider
        }

        let provider = AgentEditCLIProvider(agent: agent)
        return try await provider.generateEdit(request: request)
    }
}

private struct AgentEditCLIProvider: AgentEditProviding {
    let agent: any CodingAgentModule

    func generateEdit(request: AgentEditRequest) async throws -> AgentEditResponse {
        let command = command(for: request)
        guard !command.isEmpty else { throw AgentEditServiceError.missingCommand }

        let result = try await AgentEditProcessRunner.run(command: command, workingDirectory: request.projectPath)
        guard result.status == 0 else {
            throw AgentEditServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let replacement = cleaned(result.stdout)
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentEditServiceError.emptyResponse
        }
        return AgentEditResponse(replacement: replacement, providerID: request.provider.rawValue)
    }

    private func command(for request: AgentEditRequest) -> String {
        let prompt = InlineEditPromptBuilder.prompt(
            filePath: request.filePath,
            instruction: request.instruction,
            selectedCode: request.selectedText,
            languageID: request.languageID
        )
        let base = launchCommand(for: request.provider)
        guard !base.isEmpty else { return "" }
        return agent.startupCommand(baseCommand: base, prompt: prompt, model: request.model)
    }

    private func launchCommand(for provider: AskProvider) -> String {
        if let launcherID = provider.launcherID {
            let saved = CLILauncherSettings.shared.command(for: launcherID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !saved.isEmpty { return CLILauncherCommandResolver.resolve(saved) }
        }
        return CLILauncherCommandResolver.resolve(provider.definition?.defaultCommand ?? provider.rawValue)
    }

    private func cleaned(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

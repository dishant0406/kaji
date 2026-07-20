import Foundation

protocol CodingAgentModule: AIProviderIntegration {
    var definition: CodingAgentDefinition { get }
    var mcpServerConfigProvider: MCPServerConfigProvider? { get }

    func modelOptions() -> [String]
    func modelOptions(projectPath: String?) -> [String]
    func defaultModel(projectPath: String?) -> String?
    func startupCommand(baseCommand: String, prompt: String, model: String?) -> String
    func resumeCommand(baseCommand: String, sessionID: String, prompt: String) -> String
    func skillPrompt(skill: AskSkillOption, prompt: String) -> String
    func resolveExecutable(
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        excluding directory: URL?
    ) -> URL?
    func historyOptions(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption]
}

extension CodingAgentModule {
    var id: String { definition.id }
    var displayName: String { definition.displayName }
    var iconName: String { definition.iconName }
    var executableNames: [String] { definition.executableNames }
    var mcpServerConfigProvider: MCPServerConfigProvider? { nil }

    func modelOptions() -> [String] {
        modelOptions(projectPath: nil)
    }

    func modelOptions(projectPath _: String?) -> [String] {
        if let command = definition.modelListCommand {
            return CodingAgentCommandRunner.lines(executableName: command.executableName, arguments: command.arguments)
        }
        return definition.models
    }

    func defaultModel(projectPath _: String?) -> String? {
        definition.defaultModel
    }

    func startupCommand(baseCommand: String, prompt: String, model: String?) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = modelArguments(model)
        guard !trimmed.isEmpty else { return ([baseCommand] + arguments).joined(separator: " ") }
        return ([baseCommand] + arguments + promptArguments(ShellEscaper.escape(trimmed))).joined(separator: " ")
    }

    func resumeCommand(baseCommand: String, sessionID: String, prompt: String) -> String {
        let escapedID = ShellEscaper.escape(sessionID)
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedPrompt = trimmed.isEmpty ? nil : ShellEscaper.escape(trimmed)
        switch definition.commandProfile.resume {
        case .unsupported:
            return ""
        case let .subcommand(command):
            return [baseCommand, command, escapedID, escapedPrompt].compactMap(\.self).joined(separator: " ")
        case let .subcommandWithPromptFlag(command, promptFlag):
            return [baseCommand, command, escapedID, escapedPrompt.map { "\(promptFlag) \($0)" }]
                .compactMap(\.self)
                .joined(separator: " ")
        case let .flag(flag):
            return [baseCommand, flag, escapedID, escapedPrompt].compactMap(\.self).joined(separator: " ")
        case let .flagWithPrompt(sessionFlag, promptFlag):
            return [baseCommand, sessionFlag, escapedID, escapedPrompt.map { "\(promptFlag) \($0)" }]
                .compactMap(\.self)
                .joined(separator: " ")
        }
    }

    func skillPrompt(skill: AskSkillOption, prompt: String) -> String {
        definition.commandProfile.skillInvocation.prompt(skill: skill, userPrompt: prompt)
    }

    func resolveExecutable(
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        excluding directory: URL?
    ) -> URL? {
        for executableName in definition.executableNames {
            let path: String?
            if let directory {
                path = AIProviderExecutableLocator.preferredRealPath(
                    for: executableName,
                    env: env,
                    homeDirectory: homeDirectory,
                    fileManager: fileManager,
                    excluding: directory
                )
            } else {
                path = AIProviderExecutableLocator.resolvePath(
                    for: executableName,
                    env: env,
                    homeDirectory: homeDirectory,
                    fileManager: fileManager,
                    extraDirectories: definition.executableSearchDirectories
                )
            }
            if let path {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func historyOptions(
        projectPath _: String?,
        query _: String,
        limit _: Int,
        env _: [String: String],
        fileManager _: FileManager
    ) -> [AskHistoryOption] {
        []
    }

    func install(hookClientPath _: String) throws {}
    func uninstall() throws {}

    private func modelArguments(_ model: String?) -> [String] {
        guard let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else { return [] }
        guard let flag = definition.commandProfile.modelFlag else { return [] }
        return [flag, ShellEscaper.escape(model)]
    }

    private func promptArguments(_ escapedPrompt: String) -> [String] {
        switch definition.commandProfile.prompt {
        case .positional:
            [escapedPrompt]
        case let .flag(flag):
            [flag, escapedPrompt]
        }
    }
}

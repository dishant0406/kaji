import Foundation

@MainActor
enum ParentAgentCodingProviderCatalog {
    static func availableProviders() -> [ParentAgentCodingProviderContext] {
        AIProviderRegistry.shared.providers.compactMap { integration in
            guard integration.isEnabled, integration.isToolInstalled() else { return nil }
            guard let provider = AskProvider.resolveAnnotation(integration.id), provider != .terminal else { return nil }
            return ParentAgentCodingProviderContext(
                id: provider.rawValue,
                title: provider.title,
                installed: true,
                enabled: true,
                models: [],
                defaultModel: defaultModel(for: provider)
            )
        }
    }

    static func modelOptions(for provider: AskProvider) -> [String] {
        switch provider {
        case .codex:
            ["gpt-5.5", "gpt-5.4", "gpt-5.2-codex", "gpt-5.1-codex", "gpt-5-codex"]
        case .claude:
            ["sonnet", "opus", "haiku", "claude-sonnet-4-6", "claude-opus-4-7", "claude-haiku-4-5"]
        case .opencode:
            opencodeModels()
        case .terminal:
            []
        }
    }

    static func defaultModel(for provider: AskProvider) -> String? {
        switch provider {
        case .codex:
            "gpt-5.5"
        case .claude:
            "sonnet"
        case .opencode:
            nil
        case .terminal:
            nil
        }
    }

    private static func opencodeModels() -> [String] {
        runModelListCommand(executable: "opencode", arguments: ["models"])
    }

    private static func runModelListCommand(executable: String, arguments: [String]) -> [String] {
        guard let path = AIProviderExecutableLocator.resolvePath(for: executable) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

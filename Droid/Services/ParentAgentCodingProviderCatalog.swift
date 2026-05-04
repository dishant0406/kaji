import Foundation

@MainActor
enum ParentAgentCodingProviderCatalog {
    static func availableProviders() -> [ParentAgentCodingProviderContext] {
        AIProviderRegistry.shared.providers.compactMap { integration in
            guard let provider = AskProvider.resolveAnnotation(integration.id), provider != .terminal else { return nil }
            guard providerIsAvailable(integration, provider: provider, settings: CLILauncherSettings.shared) else { return nil }
            let agent = CodingAgentRegistry.shared.agent(id: provider.rawValue)
            return ParentAgentCodingProviderContext(
                id: provider.rawValue,
                title: provider.title,
                installed: true,
                enabled: true,
                models: [],
                defaultModel: agent?.defaultModel(projectPath: nil)
            )
        }
    }

    static func providerIsAvailable(
        _ integration: AIProviderIntegration,
        provider: AskProvider,
        settings: CLILauncherSettings
    ) -> Bool {
        guard let launcherID = provider.launcherID else { return false }
        return settings.isEnabled(id: launcherID) && integration.isToolInstalled()
    }

    static func modelOptions(for provider: AskProvider, projectPath: String? = nil) -> [String] {
        CodingAgentRegistry.shared.agent(id: provider.rawValue)?.modelOptions(projectPath: projectPath) ?? []
    }
}

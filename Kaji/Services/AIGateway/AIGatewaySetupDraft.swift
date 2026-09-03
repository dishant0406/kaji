import Foundation

struct AIGatewaySetupDraft: Equatable {
    var provider: AIGatewaySetupProviderOption
    var endpoint: String
    var modelID: String
    var apiKey: String
    var useClaude: Bool
    var useCodex: Bool

    init(
        provider: AIGatewaySetupProviderOption = .azure,
        endpoint: String = "",
        modelID: String? = nil,
        apiKey: String = "",
        useClaude: Bool = true,
        useCodex: Bool = true
    ) {
        self.provider = provider
        self.endpoint = endpoint
        self.modelID = modelID ?? provider.defaultModelID
        self.apiKey = apiKey
        self.useClaude = useClaude
        self.useCodex = useCodex
    }

    static func current(settings: AIGatewaySettings) -> AIGatewaySetupDraft {
        let route = settings.models.first?.routes.first ?? ""
        let pieces = route.split(separator: "/", maxSplits: 1).map(String.init)
        let providerID = pieces.first ?? settings.providers.first(where: \.isEnabled)?.id ?? AIGatewaySetupProviderOption.azure.providerID
        let provider = AIGatewaySetupProviderOption.option(providerID: providerID)
        let config = settings.providers.first { $0.id == provider.providerID }
        return AIGatewaySetupDraft(
            provider: provider,
            endpoint: endpointText(provider: provider, config: config),
            modelID: pieces.dropFirst().first ?? provider.defaultModelID,
            useClaude: settings.claudeConnectorEnabled && (settings.models.first?.exposeClaude ?? true),
            useCodex: settings.codexConnectorEnabled && (settings.models.first?.exposeCodex ?? true)
        )
    }

    mutating func resetProviderDefaults() {
        endpoint = ""
        modelID = provider.defaultModelID
        apiKey = ""
    }

    var trimmedEndpoint: String { endpoint.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedModelID: String { modelID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedAPIKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func endpointText(provider: AIGatewaySetupProviderOption, config: AIGatewayProviderConfiguration?) -> String {
        guard let config else { return "" }
        if provider == .azure {
            return config.resourceName.isEmpty ? config.baseURL : config.resourceName
        }
        if provider.needsCustomEndpoint {
            return config.baseURL
        }
        return ""
    }
}

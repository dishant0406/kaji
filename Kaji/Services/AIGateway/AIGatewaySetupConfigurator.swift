import Foundation

struct AIGatewaySetupConfiguration: Equatable {
    let settings: AIGatewaySettings
    let providerID: String
    let apiKey: String
}

enum AIGatewaySetupConfigurator {
    static func validationMessage(draft: AIGatewaySetupDraft, hasSavedKey: Bool) -> String? {
        if draft.provider.showsEndpoint, draft.trimmedEndpoint.isEmpty {
            return draft.provider == .azure ? "Enter your Azure resource or endpoint." : "Enter the provider endpoint."
        }
        if draft.trimmedModelID.isEmpty {
            return "Enter the model or deployment name."
        }
        if draft.provider.needsKey, !hasSavedKey, draft.trimmedAPIKey.isEmpty {
            return "Paste the provider API key."
        }
        return nil
    }

    static func configure(settings: AIGatewaySettings, draft: AIGatewaySetupDraft) -> AIGatewaySetupConfiguration {
        var copy = settings
        copy.isEnabled = true
        copy.autoStart = true
        copy.claudeConnectorEnabled = draft.useClaude
        copy.codexConnectorEnabled = draft.useCodex
        copy.providers = configuredProviders(current: settings.providers, draft: draft)
        let model = AIGatewayModelAlias(
            alias: "kaji-main",
            displayName: "Kaji Main",
            routes: [route(draft: draft)],
            exposeClaude: draft.useClaude,
            exposeCodex: draft.useCodex
        )
        copy.models = [model]
        AIGatewayModelAliasPolicy.sanitize(settings: &copy)
        return AIGatewaySetupConfiguration(settings: copy, providerID: draft.provider.providerID, apiKey: draft.trimmedAPIKey)
    }

    private static func configuredProviders(
        current: [AIGatewayProviderConfiguration],
        draft: AIGatewaySetupDraft
    ) -> [AIGatewayProviderConfiguration] {
        var providers = current
        if !providers.contains(where: { $0.id == draft.provider.providerID }) {
            providers.append(defaultProvider(for: draft.provider))
        }
        for index in providers.indices {
            providers[index].isEnabled = providers[index].id == draft.provider.providerID
            if providers[index].id == draft.provider.providerID {
                providers[index] = configuredProvider(providers[index], draft: draft)
            }
        }
        return providers
    }

    private static func configuredProvider(
        _ provider: AIGatewayProviderConfiguration,
        draft: AIGatewaySetupDraft
    ) -> AIGatewayProviderConfiguration {
        var copy = provider
        copy.isEnabled = true
        if draft.provider == .azure {
            let azure = azureEndpointParts(draft.trimmedEndpoint)
            copy.resourceName = azure.resource
            copy.baseURL = azure.baseURL
        }
        if draft.provider.needsCustomEndpoint {
            copy.baseURL = draft.trimmedEndpoint
        }
        return copy
    }

    private static func defaultProvider(for option: AIGatewaySetupProviderOption) -> AIGatewayProviderConfiguration {
        AIGatewayProviderCatalog.defaults.first { $0.id == option.providerID } ?? AIGatewayProviderConfiguration(
            id: option.providerID,
            name: option.title,
            kind: option == .customAnthropic ? .customAnthropic : .customOpenAI,
            isEnabled: false,
            baseURL: "",
            resourceName: "",
            apiKeyEnv: "CUSTOM_AI_GATEWAY_API_KEY"
        )
    }

    private static func route(draft: AIGatewaySetupDraft) -> String {
        let model = modelIDWithoutProvider(draft.trimmedModelID, providerID: draft.provider.providerID)
        return "\(draft.provider.providerID)/\(model)"
    }

    private static func modelIDWithoutProvider(_ value: String, providerID: String) -> String {
        let prefix = providerID + "/"
        guard value.hasPrefix(prefix) else { return value }
        return String(value.dropFirst(prefix.count))
    }

    private static func azureEndpointParts(_ value: String) -> (resource: String, baseURL: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.contains(".") || trimmed.contains("://") else { return (trimmed, "") }
        let urlText = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: urlText), let host = url.host else { return ("", trimmed) }
        let resource = resourceName(host: host)
        return (resource, "\(url.scheme ?? "https")://\(host)/openai/v1")
    }

    private static func resourceName(host: String) -> String {
        let suffix = ".openai.azure.com"
        guard host.hasSuffix(suffix) else { return "" }
        return String(host.dropLast(suffix.count))
    }
}

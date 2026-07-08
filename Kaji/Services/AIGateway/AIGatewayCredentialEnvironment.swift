import Foundation

enum AIGatewayCredentialEnvironment {
    static func variables(
        settings: AIGatewaySettings,
        token: String,
        credentialStore: AIGatewayCredentialStoreProtocol = AIGatewayCredentialStore.shared
    ) -> [String: String] {
        var environment = ["GATEWAY_TOKEN": token, "KAJI_GATEWAY_TOKEN": token]
        let providers = settings.providers.filter(\.isEnabled)
        for provider in providers where provider.needsAPIKey && !provider.apiKeyEnv.isEmpty {
            let key = credentialStore.load(account: AIGatewayCredentialAccount.providerKey(provider.id))
            if !key.isEmpty { environment[provider.apiKeyEnv] = key }
        }
        return environment
    }
}

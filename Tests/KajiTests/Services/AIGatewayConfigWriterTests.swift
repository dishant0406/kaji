import Testing

@testable import Kaji

@Suite("AI Gateway credential environment")
struct AIGatewayCredentialEnvironmentTests {
    @Test("exports local gateway token and enabled provider keys")
    func exportsProviderKeys() {
        let credentials = MemoryGatewayCredentials(values: [
            AIGatewayCredentialAccount.providerKey("openrouter"): "sk-openrouter",
            AIGatewayCredentialAccount.providerKey("disabled"): "sk-disabled",
        ])
        var settings = AIGatewaySettings.defaults
        settings.providers = [
            AIGatewayProviderConfiguration(
                id: "openrouter",
                name: "OpenRouter",
                kind: .preset,
                isEnabled: true,
                baseURL: "",
                resourceName: "",
                apiKeyEnv: "OPENROUTER_API_KEY"
            ),
            AIGatewayProviderConfiguration(
                id: "disabled",
                name: "Disabled",
                kind: .preset,
                isEnabled: false,
                baseURL: "",
                resourceName: "",
                apiKeyEnv: "DISABLED_API_KEY"
            ),
        ]

        let env = AIGatewayCredentialEnvironment.variables(
            settings: settings,
            token: "local-token",
            credentialStore: credentials
        )

        #expect(env["GATEWAY_TOKEN"] == "local-token")
        #expect(env["KAJI_GATEWAY_TOKEN"] == "local-token")
        #expect(env["OPENROUTER_API_KEY"] == "sk-openrouter")
        #expect(env["DISABLED_API_KEY"] == nil)
    }

    @Test("skips local providers without API keys")
    func skipsLocalProviders() {
        var settings = AIGatewaySettings.defaults
        settings.providers = [
            AIGatewayProviderConfiguration(
                id: "ollama",
                name: "Ollama",
                kind: .preset,
                isEnabled: true,
                baseURL: "",
                resourceName: "",
                apiKeyEnv: "OLLAMA_API_KEY"
            ),
        ]

        let env = AIGatewayCredentialEnvironment.variables(settings: settings, token: "token")

        #expect(env["OLLAMA_API_KEY"] == nil)
    }
}

private final class MemoryGatewayCredentials: AIGatewayCredentialStoreProtocol {
    var values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    func load(account: String) -> String { values[account] ?? "" }
    func save(_ value: String, account: String) { values[account] = value }
    func delete(account: String) { values.removeValue(forKey: account) }
}

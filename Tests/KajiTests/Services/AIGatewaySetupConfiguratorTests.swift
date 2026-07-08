import Testing

@testable import Kaji

@Suite("AI Gateway setup configurator")
struct AIGatewaySetupConfiguratorTests {
    @Test("azure quick setup creates responses route from resource name")
    func azureResourceSetup() {
        let draft = AIGatewaySetupDraft(
            provider: .azure,
            endpoint: "zerocarbon-codex",
            modelID: "gpt-5.5",
            apiKey: "azure-key",
            useClaude: true,
            useCodex: true
        )

        let result = AIGatewaySetupConfigurator.configure(settings: .defaults, draft: draft)
        let azure = result.settings.providers.first { $0.id == "azure" }

        #expect(result.providerID == "azure")
        #expect(result.apiKey == "azure-key")
        #expect(azure?.isEnabled == true)
        #expect(azure?.resourceName == "zerocarbon-codex")
        #expect(azure?.azureOpenAIBaseURL == "https://zerocarbon-codex.openai.azure.com/openai/v1")
        #expect(result.settings.models.first?.routes == ["azure/gpt-5.5"])
        #expect(AIGatewayConfigValidator.validate(result.settings) == nil)
    }

    @Test("azure quick setup accepts full endpoint")
    func azureEndpointSetup() {
        let draft = AIGatewaySetupDraft(
            provider: .azure,
            endpoint: "https://zerocarbon-codex.openai.azure.com/openai/v1",
            modelID: "azure/gpt-5.5",
            apiKey: "azure-key"
        )

        let result = AIGatewaySetupConfigurator.configure(settings: .defaults, draft: draft)
        let azure = result.settings.providers.first { $0.id == "azure" }

        #expect(azure?.resourceName == "zerocarbon-codex")
        #expect(azure?.baseURL == "https://zerocarbon-codex.openai.azure.com/openai/v1")
        #expect(result.settings.models.first?.routes == ["azure/gpt-5.5"])
    }

    @Test("validation keeps non local providers from starting without a key")
    func validationRequiresKey() {
        let draft = AIGatewaySetupDraft(provider: .openrouter, modelID: "moonshotai/kimi-k2.7-code")

        #expect(AIGatewaySetupConfigurator.validationMessage(draft: draft, hasSavedKey: false) == "Paste the provider API key.")
        #expect(AIGatewaySetupConfigurator.validationMessage(draft: draft, hasSavedKey: true) == nil)
    }

    @Test("current draft reads active route")
    func currentDraftReadsSettings() {
        var settings = AIGatewaySettings.defaults
        settings.providers = AIGatewaySetupConfigurator.configure(
            settings: settings,
            draft: AIGatewaySetupDraft(provider: .openrouter, modelID: "openrouter/kimi")
        ).settings.providers
        settings.models = [AIGatewayModelAlias(alias: "kaji-main", displayName: "Kaji Main", routes: ["openrouter/kimi"])]

        let draft = AIGatewaySetupDraft.current(settings: settings)

        #expect(draft.provider == .openrouter)
        #expect(draft.modelID == "kimi")
    }
}

import Testing
@testable import Kaji

struct KajiAgentCustomProviderTests {
    @Test
    func encodesManualProviderPayload() {
        let provider = KajiAgentCustomProvider(
            id: "myco",
            baseUrl: "https://llm.internal/v1",
            apiKey: "MYCO_API_KEY",
            api: .openAIResponses,
            auth: .apiKey,
            headersText: "X-Org-Id: team-a",
            disableStrictTools: true,
            models: [
                KajiAgentCustomProviderModel(
                    modelID: "myco-large",
                    name: "MyCo Large",
                    reasoning: true,
                    supportsText: true,
                    supportsImage: true,
                    contextWindow: "200000",
                    maxTokens: "32000"
                ),
            ]
        )

        let object = provider.json.objectValue ?? [:]
        #expect(object["id"]?.stringValue == "myco")
        #expect(object["api"]?.stringValue == "openai-responses")
        #expect(object["headers"]?.objectValue?["X-Org-Id"]?.stringValue == "team-a")
        let model = object["models"]?.arrayValue?.first?.objectValue
        #expect(model?["id"]?.stringValue == "myco-large")
        #expect(model?["reasoning"]?.boolValue == true)
        #expect(model?["contextWindow"]?.numberAsInt == 200000)
    }

    @Test
    func parsesProviderListResponse() {
        let state = KajiAgentCustomProvidersState(json: .object([
            "path": .string("/tmp/models.yml"),
            "providers": .array([
                .object([
                    "id": .string("llama.cpp"),
                    "baseUrl": .string("http://127.0.0.1:8080"),
                    "api": .string("openai-responses"),
                    "auth": .string("none"),
                    "discovery": .object(["type": .string("llama.cpp")]),
                    "modelCount": .number(0),
                    "isOverrideOnly": .bool(true),
                ]),
            ]),
        ]))

        #expect(state.path == "/tmp/models.yml")
        #expect(state.providers.count == 1)
        #expect(state.providers[0].id == "llama.cpp")
        #expect(state.providers[0].auth == .none)
        #expect(state.providers[0].discovery == .llamaCpp)
    }

    @Test
    func validatesProviderDraft() {
        let invalid = KajiAgentCustomProvider(id: "bad provider", apiKey: "KEY", models: [])
        #expect(!invalid.canSave)

        let valid = KajiAgentCustomProvider(
            id: "local",
            baseUrl: "http://127.0.0.1:8080",
            api: .openAIResponses,
            auth: .none,
            discovery: .llamaCpp,
            models: []
        )
        #expect(valid.canSave)
    }

    @Test
    func encodesAzureDeploymentDiscovery() {
        let provider = KajiAgentCustomProvider(
            id: "zerocarbon-codex",
            baseUrl: "https://zerocarbon-codex.openai.azure.com/openai/v1",
            apiKey: "AZURE_OPENAI_API_KEY",
            api: .azureOpenAIResponses,
            discovery: .azureOpenAIDeployments,
            azureResourceGroup: "DefaultResourceGroup-eastus2",
            azureAccountName: "zerocarbon-codex",
            azureSubscription: "sub",
            models: []
        )

        let discovery = provider.json.objectValue?["discovery"]?.objectValue
        #expect(provider.canSave)
        #expect(provider.canAutoMatchModels)
        #expect(discovery?["type"]?.stringValue == "azure-openai-deployments")
        #expect(discovery?["resourceGroup"]?.stringValue == "DefaultResourceGroup-eastus2")
        #expect(discovery?["accountName"]?.stringValue == "zerocarbon-codex")
        #expect(discovery?["subscription"]?.stringValue == "sub")
    }

    @Test
    func parsesAutoMatchResult() {
        let result = KajiAgentCustomProviderAutoMatch(json: .object([
            "account": .object([
                "name": .string("zerocarbon-codex"),
                "resourceGroup": .string("DefaultResourceGroup-eastus2"),
            ]),
            "models": .array([
                .object([
                    "id": .string("gpt-5.5"),
                    "name": .string("GPT 5.5"),
                    "reasoning": .bool(true),
                    "input": .array([.string("text"), .string("image")]),
                ]),
            ]),
        ]))

        #expect(result.accountName == "zerocarbon-codex")
        #expect(result.resourceGroup == "DefaultResourceGroup-eastus2")
        #expect(result.models.count == 1)
        #expect(result.models[0].modelID == "gpt-5.5")
        #expect(result.models[0].supportsImage)
    }
}

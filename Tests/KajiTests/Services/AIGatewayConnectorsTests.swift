import Testing

@testable import Kaji

@Suite("AI Gateway agent connectors")
struct AIGatewayConnectorsTests {
    @Test("codex merge replaces gateway block and preserves unrelated config")
    func codexMerge() {
        var settings = AIGatewaySettings.defaults
        settings.port = 4444
        settings.models = [AIGatewayModelAlias(alias: "kimi", displayName: "Kimi", routes: ["openrouter/kimi"])]
        let existing = """
        approval_policy = "never"
        model = "old"
        model_provider = "old_provider"

        [model_providers.other]
        name = "Other"

        [model_providers.kaji_gateway]
        name = "Old"
        base_url = "http://old"
        """

        let merged = AIGatewayCodexConnector.mergedConfig(existing, settings: settings)

        #expect(merged.contains("approval_policy = \"never\""))
        #expect(merged.contains("[model_providers.other]"))
        #expect(merged.contains("model = \"Fusion/kimi\""))
        #expect(merged.contains("model_provider = \"kaji_gateway\""))
        #expect(merged.contains("base_url = \"http://localhost:4444/v1\""))
        #expect(!merged.contains("http://old"))
    }

    @Test("claude model merge preserves existing models")
    func claudeMerge() {
        var settings = AIGatewaySettings.defaults
        settings.models = [AIGatewayModelAlias(alias: "kimi", displayName: "Kimi", routes: ["openrouter/kimi"])]

        let merged = AIGatewayClaudeConnector.mergedSettings(["availableModels": ["sonnet"]], settings: settings)
        let models = merged["availableModels"] as? [String]

        #expect(models == ["sonnet", "Fusion/kimi"])
    }

    @Test("claude merge removes Kaji CCR profile auth conflicts")
    func claudeMergeRemovesManagedProfileState() {
        var settings = AIGatewaySettings.defaults
        settings.port = 5254
        let existing: [String: Any] = [
            "apiKeyHelper": "/Users/me/Library/Application Support/Kaji/ai-gateway/claude-code-router/home/.claude-code-router/bin/ccr-claude-code-api-key-kaji-claude-code",
            "env": [
                "ANTHROPIC_BASE_URL": "http://127.0.0.1:5254",
                "ANTHROPIC_MODEL": "Azure AI Foundry/gpt-5.5",
                "USER_VALUE": "keep",
            ],
        ]

        let merged = AIGatewayClaudeConnector.mergedSettings(existing, settings: settings)
        let env = merged["env"] as? [String: Any]

        #expect(merged["apiKeyHelper"] == nil)
        #expect(env?["ANTHROPIC_BASE_URL"] == nil)
        #expect(env?["ANTHROPIC_MODEL"] == nil)
        #expect(env?["USER_VALUE"] as? String == "keep")
    }

    @Test("instructions include gateway endpoints")
    func instructions() {
        var settings = AIGatewaySettings.defaults
        settings.port = 4555
        let claude = AIGatewayInstructionBuilder.claude(settings: settings, token: "tok")
        let codex = AIGatewayInstructionBuilder.codex(settings: settings, token: "tok")

        #expect(claude.contains("ANTHROPIC_BASE_URL=\"http://localhost:4555\""))
        #expect(claude.contains("ANTHROPIC_AUTH_TOKEN=\"tok\""))
        #expect(claude.contains("claude --model Fusion/kaji-main"))
        #expect(codex.contains("KAJI_GATEWAY_TOKEN=\"tok\""))
        #expect(codex.contains("codex --model Fusion/kaji-main"))
    }
}

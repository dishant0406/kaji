import Foundation
import Testing

@testable import Kaji

@Suite("Claude Code Router gateway backend")
struct AIGatewayClaudeCodeRouterTests {
    @Test("node runtime accepts only node 22 and newer")
    func nodeVersionSupport() {
        #expect(AIGatewayNodeRuntimeResolver.supportsNode22("v22.15.0"))
        #expect(AIGatewayNodeRuntimeResolver.supportsNode22("23.0.0"))
        #expect(!AIGatewayNodeRuntimeResolver.supportsNode22("v21.9.0"))
        #expect(!AIGatewayNodeRuntimeResolver.supportsNode22("not-a-version"))
    }

    @Test("managed Node archive uses pinned Node 22")
    func managedNodeArchiveUsesPinnedRuntime() throws {
        let url = try AIGatewayManagedNodeInstaller.archiveURL(architecture: "arm64")

        #expect(url.absoluteString.contains("node-v22.15.0-darwin-arm64.tar.gz"))
    }

    @Test("installer pins the external CCR package")
    func installerPinsPackage() {
        #expect(AIGatewayClaudeCodeRouterPaths.packageName == "@musistudio/claude-code-router")
        #expect(AIGatewayClaudeCodeRouterInstaller.installArguments().contains("@musistudio/claude-code-router@3.0.1"))
        #expect(AIGatewayClaudeCodeRouterInstaller.installArguments().contains("--omit=dev"))
    }

    @Test("CCR config uses Kaji ports, env keys, and disabled proxy defaults")
    func configUsesSafeDefaults() throws {
        var settings = AIGatewaySettings.defaults
        settings.providers = settings.providers.map { provider in
            var copy = provider
            copy.isEnabled = copy.id == "azure"
            if copy.id == "azure" { copy.resourceName = "zerocarbon-codex" }
            return copy
        }
        settings.models = [AIGatewayModelAlias(alias: "kaji-main", displayName: "Kaji Main", routes: ["azure/gpt-5.5"])]

        let config = AIGatewayClaudeCodeRouterConfigWriter.build(settings: settings, token: "local-token")
        let providers = try #require(config["Providers"] as? [[String: Any]])
        let azure = try #require(providers.first)
        let router = try #require(config["Router"] as? [String: Any])
        let rules = try #require(router["rules"] as? [[String: Any]])
        let profiles = try #require(config["virtualModelProfiles"] as? [[String: Any]])
        let profile = try #require(profiles.first)
        let baseModel = try #require(profile["baseModel"] as? [String: Any])
        let proxy = try #require(config["proxy"] as? [String: Any])
        let gateway = try #require(config["gateway"] as? [String: Any])
        let plugins = try #require(config["plugins"] as? [[String: Any]])
        let plugin = try #require(plugins.first)

        #expect(config["PORT"] as? Int == 5254)
        #expect(gateway["corePort"] as? Int == 5255)
        #expect(azure["id"] as? String == "azure")
        #expect(azure["name"] as? String == "Azure AI Foundry")
        #expect(azure["api_base_url"] as? String == "https://zerocarbon-codex.openai.azure.com/openai/v1")
        #expect(azure["api_key"] as? String == "$AZURE_AI_API_KEY")
        #expect(azure["type"] as? String == "openai_responses")
        #expect(rules.isEmpty)
        #expect(profile["key"] as? String == "kaji-main")
        #expect(baseModel["fixedModel"] as? String == "azure/gpt-5.5")
        #expect(proxy["enabled"] as? Bool == false)
        #expect(proxy["systemProxy"] as? Bool == false)
        #expect(proxy["captureNetwork"] as? Bool == false)
        #expect(plugin["key"] as? String == "kaji-openai-responses")
        #expect(plugin["modulePath"] as? String == AIGatewayClaudeCodeRouterPaths.openAIResponsesPluginURL().path)
    }

    @Test("CCR virtual models expose kaji names")
    func virtualModelsExposeKajiNames() throws {
        var settings = AIGatewaySettings.defaults
        settings.providers = settings.providers.map { provider in
            var copy = provider
            copy.isEnabled = copy.id == "openai"
            return copy
        }
        settings.models = [AIGatewayModelAlias(alias: "main", displayName: "Main", routes: ["openai/gpt-5.1"])]

        let config = AIGatewayClaudeCodeRouterConfigWriter.build(settings: settings, token: "token")
        let profiles = try #require(config["virtualModelProfiles"] as? [[String: Any]])
        let profile = try #require(profiles.first)
        let match = try #require(profile["match"] as? [String: Any])
        let aliases = try #require(match["exactAliases"] as? [String])
        let baseModel = try #require(profile["baseModel"] as? [String: Any])

        #expect(profile["id"] as? String == "kaji-main")
        #expect(aliases == ["kaji-main"])
        #expect(baseModel["fixedModel"] as? String == "openai/gpt-5.1")
    }

    @Test("CCR config uses neutral identity for OpenAI compatible non OpenAI providers")
    func usesNeutralProviderIdentity() throws {
        var settings = AIGatewaySettings.defaults
        settings.providers = [
            AIGatewayProviderConfiguration(
                id: "custom-openai",
                name: "Custom OpenAI Compatible",
                kind: .customOpenAI,
                isEnabled: true,
                baseURL: "https://proxy.example.com/v1",
                resourceName: "",
                apiKeyEnv: "CUSTOM_OPENAI_API_KEY"
            ),
        ]
        settings.models = [AIGatewayModelAlias(alias: "proxy", displayName: "Proxy", routes: ["custom-openai/gpt-compatible"])]

        let config = AIGatewayClaudeCodeRouterConfigWriter.build(settings: settings, token: "token")
        let providers = try #require(config["Providers"] as? [[String: Any]])
        let provider = try #require(providers.first)
        let profiles = try #require(config["virtualModelProfiles"] as? [[String: Any]])
        let profile = try #require(profiles.first)
        let baseModel = try #require(profile["baseModel"] as? [String: Any])

        #expect(provider["id"] as? String == "custom-ai")
        #expect(provider["name"] as? String == "Custom AI Compatible")
        #expect(baseModel["fixedModel"] as? String == "custom-ai/gpt-compatible")
    }

    @Test("CCR profile management stays disabled")
    func profileManagementDisabled() throws {
        let config = AIGatewayClaudeCodeRouterConfigWriter.build(settings: .defaults, token: "token")
        let profile = try #require(config["profile"] as? [String: Any])
        let profiles = try #require(profile["profiles"] as? [Any])

        #expect(profile["enabled"] as? Bool == false)
        #expect(profiles.isEmpty)
    }

    @Test("CCR config cleanup removes stale sqlite config state")
    func cleanupRemovesStaleSQLiteConfigState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = AIGatewayClaudeCodeRouterStateCleaner.stateURLs(configDirectory: directory)
        for url in urls { try Data("stale".utf8).write(to: url) }

        try AIGatewayClaudeCodeRouterStateCleaner.removePersistedConfig(configDirectory: directory)

        #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("CCR plugin maps assistant history to responses output text")
    func pluginMapsAssistantHistoryToOutputText() throws {
        let source = AIGatewayClaudeCodeRouterPluginWriter.source

        #expect(source.contains("role === \"assistant\" ? \"output_text\" : \"input_text\""))
        #expect(source.contains("providerTypes: [\"openai_responses\"]"))
        #expect(!source.contains("role, content: [{ type: \"input_text\", text }]"))
    }

    @Test("CCR gateway entry injects Kaji plugin before external gateway boot")
    func gatewayEntryInjectsPlugin() {
        let source = AIGatewayClaudeCodeRouterGatewayEntryWriter.source

        #expect(source.contains("GATEWAY_CONFIG_PATH"))
        #expect(source.contains("KAJI_CCR_OPENAI_RESPONSES_PLUGIN"))
        #expect(source.contains("@the-next-ai"))
    }

    @Test("CCR launch environment points core gateway at Kaji entry")
    @MainActor
    func launchEnvironmentUsesKajiGatewayEntry() {
        let controller = AIGatewayRuntimeController()
        let env = controller.launchEnvironment(settings: .defaults, token: "token")

        #expect(env["CCR_GATEWAY_ENTRY"] == AIGatewayClaudeCodeRouterPaths.gatewayEntryURL().path)
        #expect(env["KAJI_CCR_OPENAI_RESPONSES_PLUGIN"] == AIGatewayClaudeCodeRouterPaths.openAIResponsesPluginURL().path)
    }

    @Test("reserved model aliases are made gateway safe")
    func reservedAliasesAreSafe() {
        #expect(AIGatewayModelAliasPolicy.sanitized("main") == "kaji-main")
        #expect(AIGatewayModelAliasPolicy.sanitized("subagent") == "kaji-subagent")
        #expect(AIGatewayModelAliasPolicy.sanitized("kimi") == "kimi")
    }

}

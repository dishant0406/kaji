import Foundation

enum AIGatewayClaudeCodeRouterConfigWriter {
    static func write(
        settings: AIGatewaySettings,
        token: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let config = build(settings: settings, token: token)
        let url = AIGatewayClaudeCodeRouterPaths.configURL()
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try AIGatewayClaudeCodeRouterPluginWriter.writeOpenAIResponsesPlugin(fileManager: fileManager)
        try AIGatewayClaudeCodeRouterGatewayEntryWriter.write(fileManager: fileManager)
        try AIGatewayClaudeCodeRouterStateCleaner.removePersistedConfig(fileManager: fileManager)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    static func build(settings: AIGatewaySettings, token: String) -> [String: Any] {
        let providers = providerObjects(settings: settings)
        let virtualModels = virtualModelProfiles(settings: settings)
        return [
            "APIKEY": token,
            "APIKEYS": [["createdAt": isoDate(), "id": "kaji-local", "key": token, "name": "Kaji Local"]],
            "HOST": settings.bindAddress,
            "PORT": settings.normalizedPort,
            "Providers": providers,
            "Router": router(),
            "gateway": gateway(settings: settings),
            "observability": ["agentAnalysis": false, "requestLogs": false],
            "plugins": AIGatewayClaudeCodeRouterPluginWriter.plugins(),
            "profile": profile(),
            "proxy": proxy(),
            "routerEndpoint": settings.endpointBaseURL,
            "toolHub": ["browserAutomation": false, "enabled": false],
            "virtualModelProfiles": virtualModels,
        ]
    }

    private static func providerObjects(settings: AIGatewaySettings) -> [[String: Any]] {
        let routes = routeModels(settings: settings)
        return settings.providers.filter(\.isEnabled).compactMap { provider in
            let models = Array(routes[provider.id] ?? []).sorted()
            guard !models.isEmpty else { return nil }
            var object: [String: Any] = [
                "id": providerIdentity(provider),
                "name": providerDisplayName(provider),
                "models": models,
                "type": protocolName(provider),
            ]
            if let baseURL = baseURL(provider) { object["api_base_url"] = baseURL }
            if provider.needsAPIKey, !provider.apiKeyEnv.isEmpty { object["api_key"] = "$\(provider.apiKeyEnv)" }
            return object
        }
    }

    private static func virtualModelProfiles(settings: AIGatewaySettings) -> [[String: Any]] {
        let providersByID = Dictionary(uniqueKeysWithValues: settings.providers.map { ($0.id, $0) })
        return settings.models.compactMap { model in
            guard let route = model.routes.first else { return nil }
            let parts = route.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let provider = providersByID[parts[0]] else { return nil }
            let alias = AIGatewayModelAliasPolicy.sanitized(model.alias)
            return [
                "baseModel": ["fixedModel": "\(providerIdentity(provider))/\(parts[1])", "mode": "fixed"],
                "displayName": model.displayName,
                "enabled": true,
                "id": alias,
                "key": alias,
                "match": ["exactAliases": [alias]],
                "materialization": ["enabled": true, "includeInGatewayModels": true],
            ]
        }
    }

    private static func routeModels(settings: AIGatewaySettings) -> [String: Set<String>] {
        var output = [String: Set<String>]()
        for model in settings.models {
            for route in model.routes {
                let parts = route.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                output[parts[0], default: []].insert(parts[1])
            }
        }
        return output
    }

    private static func router() -> [String: Any] {
        [
            "builtInRules": ["claude-code": ["enabled": true], "codex": ["enabled": true]],
            "fallback": ["mode": "off", "models": [], "retryCount": 1],
            "rules": [],
        ]
    }

    private static func gateway(settings: AIGatewaySettings) -> [String: Any] {
        [
            "coreHost": "127.0.0.1",
            "corePort": min(settings.normalizedPort + 1, 65535),
            "enabled": true,
            "host": settings.bindAddress,
            "port": settings.normalizedPort,
        ]
    }

    private static func profile() -> [String: Any] {
        [
            "claudeCode": ["enabled": false],
            "codex": ["enabled": false],
            "enabled": false,
            "profiles": [],
        ]
    }

    private static func proxy() -> [String: Any] {
        [
            "browserMode": true,
            "captureNetwork": false,
            "enabled": false,
            "host": "127.0.0.1",
            "mode": "gateway",
            "port": 7890,
            "systemProxy": false,
            "targets": [],
        ]
    }

    private static func providerIdentity(_ provider: AIGatewayProviderConfiguration) -> String {
        if provider.id == "openai" { return provider.id }
        return neutralProviderIdentity(provider.id)
    }

    private static func providerDisplayName(_ provider: AIGatewayProviderConfiguration) -> String {
        switch provider.kind {
        case .azure: "Azure AI Foundry"
        case .customOpenAI: "Custom AI Compatible"
        case .customAnthropic: "Custom Anthropic Compatible"
        case .preset: provider.name
        }
    }

    private static func neutralProviderIdentity(_ value: String) -> String {
        value
            .replacingOccurrences(of: "openai", with: "ai", options: [.caseInsensitive])
            .replacingOccurrences(of: "open-ai", with: "ai", options: [.caseInsensitive])
            .replacingOccurrences(of: "open_ai", with: "ai", options: [.caseInsensitive])
    }

    private static func baseURL(_ provider: AIGatewayProviderConfiguration) -> String? {
        switch provider.kind {
        case .azure: provider.azureOpenAIBaseURL
        case .customOpenAI,
             .customAnthropic: provider.baseURL
        case .preset: presetBaseURL(provider.id)
        }
    }

    private static func protocolName(_ provider: AIGatewayProviderConfiguration) -> String {
        if provider.kind == .customAnthropic || provider.id == "anthropic" { return "anthropic_messages" }
        if provider.id == "ollama" { return "openai_chat_completions" }
        return "openai_responses"
    }

    private static func presetBaseURL(_ id: String) -> String? {
        [
            "ollama": "http://localhost:11434/v1",
            "openai": "https://api.openai.com/v1",
            "anthropic": "https://api.anthropic.com",
            "openrouter": "https://openrouter.ai/api/v1",
        ][id]
    }

    private static func isoDate() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

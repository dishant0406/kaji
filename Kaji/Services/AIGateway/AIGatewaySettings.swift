import Foundation

struct AIGatewaySettings: Codable, Equatable {
    var isEnabled: Bool
    var autoStart: Bool
    var bindAddress: String
    var port: Int
    var providers: [AIGatewayProviderConfiguration]
    var models: [AIGatewayModelAlias]
    var claudeConnectorEnabled: Bool
    var codexConnectorEnabled: Bool

    static let defaults = AIGatewaySettings(
        isEnabled: false,
        autoStart: true,
        bindAddress: "127.0.0.1",
        port: 5254,
        providers: AIGatewayProviderCatalog.defaults,
        models: [AIGatewayModelAlias(alias: "kaji-main", displayName: "Kaji Main", routes: ["ollama/qwen2.5-coder:latest"])],
        claudeConnectorEnabled: true,
        codexConnectorEnabled: true
    )

    var endpointBaseURL: String { "http://localhost:\(normalizedPort)" }
    var anthropicBaseURL: String { endpointBaseURL }
    var openAIBaseURL: String { endpointBaseURL + "/v1" }
    var serverBind: String { "\(bindAddress.trimmingCharacters(in: .whitespacesAndNewlines)):\(normalizedPort)" }
    var normalizedPort: Int { min(max(port, 1), 65535) }
}

struct AIGatewayProviderConfiguration: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: AIGatewayProviderKind
    var isEnabled: Bool
    var baseURL: String
    var resourceName: String
    var apiKeyEnv: String

    var needsAPIKey: Bool { id != "ollama" }
    var isCustom: Bool { kind == .customOpenAI || kind == .customAnthropic }
    var azureOpenAIBaseURL: String {
        if !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return baseURL
        }
        let resource = resourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resource.isEmpty else { return "" }
        return "https://\(resource).openai.azure.com/openai/v1"
    }
}

struct AIGatewayModelAlias: Codable, Equatable, Identifiable {
    var alias: String
    var displayName: String
    var routes: [String]
    var exposeClaude: Bool
    var exposeCodex: Bool

    var id: String { alias }

    init(
        alias: String,
        displayName: String,
        routes: [String],
        exposeClaude: Bool = true,
        exposeCodex: Bool = true
    ) {
        self.alias = alias
        self.displayName = displayName
        self.routes = routes
        self.exposeClaude = exposeClaude
        self.exposeCodex = exposeCodex
    }
}

enum AIGatewayProviderKind: String, Codable, CaseIterable, Identifiable {
    case preset
    case azure
    case customOpenAI
    case customAnthropic

    var id: String { rawValue }
}

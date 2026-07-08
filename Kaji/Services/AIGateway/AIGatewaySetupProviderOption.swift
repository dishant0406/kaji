import Foundation

enum AIGatewaySetupProviderOption: String, CaseIterable, Codable, Hashable, Identifiable {
    case ollama
    case azure
    case openrouter
    case openai
    case anthropic
    case customOpenAI
    case customAnthropic

    var id: String { rawValue }

    var providerID: String {
        switch self {
        case .ollama: "ollama"
        case .azure: "azure"
        case .openrouter: "openrouter"
        case .openai: "openai"
        case .anthropic: "anthropic"
        case .customOpenAI: "custom-openai"
        case .customAnthropic: "custom-anthropic"
        }
    }

    var title: String {
        switch self {
        case .ollama: "Ollama"
        case .azure: "Azure OpenAI"
        case .openrouter: "OpenRouter"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .customOpenAI: "Custom OpenAI"
        case .customAnthropic: "Custom Anthropic"
        }
    }

    var needsKey: Bool { self != .ollama }
    var needsAzureEndpoint: Bool { self == .azure }
    var needsCustomEndpoint: Bool { self == .customOpenAI || self == .customAnthropic }
    var showsEndpoint: Bool { needsAzureEndpoint || needsCustomEndpoint }

    var defaultModelID: String {
        switch self {
        case .ollama: "qwen2.5-coder:latest"
        case .azure: "gpt-5.5"
        case .openrouter: "moonshotai/kimi-k2.7-code"
        case .openai: "gpt-5.1"
        case .anthropic: "claude-sonnet-4-6"
        case .customOpenAI,
             .customAnthropic: "model-id"
        }
    }

    var endpointPlaceholder: String {
        switch self {
        case .azure: "zerocarbon-codex or https://resource.openai.azure.com"
        case .customOpenAI: "https://api.example.com/v1"
        case .customAnthropic: "https://api.example.com"
        default: ""
        }
    }

    static func option(providerID: String) -> AIGatewaySetupProviderOption {
        allCases.first { $0.providerID == providerID } ?? .customOpenAI
    }
}

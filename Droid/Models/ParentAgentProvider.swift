import Foundation

struct ParentAgentProvider: Identifiable, Hashable {
    let id: String
    let title: String
    let defaultModel: String
    let models: [String]
    let environmentKeys: [String]
    let authKey: String
    let oauthKey: String?
    let supportsThinking: Bool
}

enum ParentAgentProviderRegistry {
    static let defaultProviderID = "anthropic"
    static let defaultModelID = "claude-sonnet-4-5"

    static let providers: [ParentAgentProvider] = [
        ParentAgentProvider(
            id: "anthropic",
            title: "Anthropic",
            defaultModel: "claude-sonnet-4-5",
            models: ["claude-sonnet-4-5", "claude-sonnet-4-6", "claude-opus-4-7", "claude-haiku-4-5"],
            environmentKeys: ["ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"],
            authKey: "anthropic",
            oauthKey: "anthropic",
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "openai-codex",
            title: "ChatGPT / Codex",
            defaultModel: "gpt-5.5",
            models: ["gpt-5.5", "gpt-5.4", "gpt-5.1"],
            environmentKeys: ["OPENAI_CODEX_OAUTH_TOKEN"],
            authKey: "openai-codex",
            oauthKey: "openai-codex",
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "github-copilot",
            title: "GitHub Copilot",
            defaultModel: "gpt-5.4",
            models: ["gpt-5.4", "claude-sonnet-4-5", "gemini-3.1-pro-preview"],
            environmentKeys: ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"],
            authKey: "github-copilot",
            oauthKey: "github-copilot",
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "openai",
            title: "OpenAI",
            defaultModel: "gpt-5.4",
            models: ["gpt-5.4", "gpt-5.1", "gpt-4.1"],
            environmentKeys: ["OPENAI_API_KEY"],
            authKey: "openai",
            oauthKey: nil,
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "google",
            title: "Google Gemini",
            defaultModel: "gemini-3.1-pro-preview",
            models: ["gemini-3.1-pro-preview", "gemini-2.5-pro", "gemini-2.5-flash"],
            environmentKeys: ["GEMINI_API_KEY"],
            authKey: "google",
            oauthKey: nil,
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "zai",
            title: "ZAI",
            defaultModel: "glm-5.1",
            models: ["glm-5.1", "glm-4.7"],
            environmentKeys: ["ZAI_API_KEY"],
            authKey: "zai",
            oauthKey: nil,
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "kimi-coding",
            title: "Kimi For Coding",
            defaultModel: "kimi-for-coding",
            models: ["kimi-for-coding"],
            environmentKeys: ["KIMI_API_KEY"],
            authKey: "kimi-coding",
            oauthKey: nil,
            supportsThinking: false
        ),
        ParentAgentProvider(
            id: "openrouter",
            title: "OpenRouter",
            defaultModel: "moonshotai/kimi-k2.6",
            models: ["moonshotai/kimi-k2.6", "anthropic/claude-sonnet-4.5", "openai/gpt-5.1"],
            environmentKeys: ["OPENROUTER_API_KEY"],
            authKey: "openrouter",
            oauthKey: nil,
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "xai",
            title: "xAI",
            defaultModel: "grok-4.20-0309-reasoning",
            models: ["grok-4.20-0309-reasoning", "grok-4"],
            environmentKeys: ["XAI_API_KEY"],
            authKey: "xai",
            oauthKey: nil,
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "deepseek",
            title: "DeepSeek",
            defaultModel: "deepseek-v4-pro",
            models: ["deepseek-v4-pro", "deepseek-chat"],
            environmentKeys: ["DEEPSEEK_API_KEY"],
            authKey: "deepseek",
            oauthKey: nil,
            supportsThinking: true
        ),
        ParentAgentProvider(
            id: "mistral",
            title: "Mistral",
            defaultModel: "devstral-medium-latest",
            models: ["devstral-medium-latest", "mistral-large-latest"],
            environmentKeys: ["MISTRAL_API_KEY"],
            authKey: "mistral",
            oauthKey: nil,
            supportsThinking: false
        ),
        ParentAgentProvider(
            id: "groq",
            title: "Groq",
            defaultModel: "openai/gpt-oss-120b",
            models: ["openai/gpt-oss-120b"],
            environmentKeys: ["GROQ_API_KEY"],
            authKey: "groq",
            oauthKey: nil,
            supportsThinking: false
        ),
    ]

    static func provider(id: String) -> ParentAgentProvider {
        providers.first { $0.id == id } ?? providers[0]
    }

    static func modelOptions(for providerID: String) -> [String] {
        provider(id: providerID).models
    }
}

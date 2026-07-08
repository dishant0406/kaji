import Foundation

enum AIGatewayProviderCatalog {
    static let defaults: [AIGatewayProviderConfiguration] = [
        provider("ollama", "Ollama", isEnabled: true, apiKeyEnv: "OLLAMA_API_KEY"),
        provider("openrouter", "OpenRouter", apiKeyEnv: "OPENROUTER_API_KEY"),
        provider("openai", "OpenAI", apiKeyEnv: "OPENAI_API_KEY"),
        provider("anthropic", "Anthropic", apiKeyEnv: "ANTHROPIC_API_KEY"),
        provider("moonshot", "Moonshot", apiKeyEnv: "MOONSHOT_API_KEY"),
        provider("fireworks", "Fireworks", apiKeyEnv: "FIREWORKS_API_KEY"),
        provider("together", "Together", apiKeyEnv: "TOGETHER_API_KEY"),
        provider("groq", "Groq", apiKeyEnv: "GROQ_API_KEY"),
        provider("deepinfra", "DeepInfra", apiKeyEnv: "DEEPINFRA_API_KEY"),
        provider("deepseek", "DeepSeek", apiKeyEnv: "DEEPSEEK_API_KEY"),
        provider("mistral", "Mistral", apiKeyEnv: "MISTRAL_API_KEY"),
        provider("xai", "xAI", apiKeyEnv: "XAI_API_KEY"),
        provider("cerebras", "Cerebras", apiKeyEnv: "CEREBRAS_API_KEY"),
        AIGatewayProviderConfiguration(
            id: "azure",
            name: "Azure OpenAI",
            kind: .azure,
            isEnabled: false,
            baseURL: "",
            resourceName: "",
            apiKeyEnv: "AZURE_AI_API_KEY"
        ),
        AIGatewayProviderConfiguration(
            id: "custom-openai",
            name: "Custom OpenAI Compatible",
            kind: .customOpenAI,
            isEnabled: false,
            baseURL: "http://localhost:8000/v1",
            resourceName: "",
            apiKeyEnv: "CUSTOM_OPENAI_API_KEY"
        ),
        AIGatewayProviderConfiguration(
            id: "custom-anthropic",
            name: "Custom Anthropic Compatible",
            kind: .customAnthropic,
            isEnabled: false,
            baseURL: "http://localhost:8001",
            resourceName: "",
            apiKeyEnv: "CUSTOM_ANTHROPIC_API_KEY"
        ),
    ]

    private static func provider(
        _ id: String,
        _ name: String,
        isEnabled: Bool = false,
        apiKeyEnv: String
    ) -> AIGatewayProviderConfiguration {
        AIGatewayProviderConfiguration(
            id: id,
            name: name,
            kind: .preset,
            isEnabled: isEnabled,
            baseURL: "",
            resourceName: "",
            apiKeyEnv: apiKeyEnv
        )
    }
}

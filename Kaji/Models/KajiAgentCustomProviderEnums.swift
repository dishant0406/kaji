enum KajiAgentCustomProviderAPI: String, CaseIterable, Identifiable {
    case providerDefault = ""
    case openAICompletions = "openai-completions"
    case openAIResponses = "openai-responses"
    case openAICodexResponses = "openai-codex-responses"
    case azureOpenAIResponses = "azure-openai-responses"
    case anthropicMessages = "anthropic-messages"
    case googleGenerativeAI = "google-generative-ai"
    case googleVertex = "google-vertex"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providerDefault: "Provider default"
        case .openAICompletions: "OpenAI Chat Completions"
        case .openAIResponses: "OpenAI Responses"
        case .openAICodexResponses: "OpenAI Codex Responses"
        case .azureOpenAIResponses: "Azure OpenAI Responses"
        case .anthropicMessages: "Anthropic Messages"
        case .googleGenerativeAI: "Google Generative AI"
        case .googleVertex: "Google Vertex"
        }
    }
}

enum KajiAgentCustomProviderAuth: String, CaseIterable, Identifiable {
    case apiKey
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apiKey: "API key"
        case .none: "None"
        }
    }
}

enum KajiAgentCustomProviderDiscovery: String, CaseIterable, Identifiable {
    case none = ""
    case ollama
    case llamaCpp = "llama.cpp"
    case lmStudio = "lm-studio"
    case openAIModelsList = "openai-models-list"
    case proxy
    case azureOpenAIDeployments = "azure-openai-deployments"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Manual models"
        case .ollama: "Ollama"
        case .llamaCpp: "llama.cpp"
        case .lmStudio: "LM Studio"
        case .openAIModelsList: "OpenAI models list"
        case .proxy: "Proxy"
        case .azureOpenAIDeployments: "Azure OpenAI deployments"
        }
    }
}

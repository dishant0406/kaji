import Foundation

struct KajiAgentCustomProvider: Identifiable, Hashable {
    var id: String
    var baseUrl: String
    var apiKey: String
    var api: KajiAgentCustomProviderAPI
    var auth: KajiAgentCustomProviderAuth
    var discovery: KajiAgentCustomProviderDiscovery
    var azureResourceGroup: String
    var azureAccountName: String
    var azureSubscription: String
    var headersText: String
    var disableStrictTools: Bool
    var models: [KajiAgentCustomProviderModel]
    var isOverrideOnly: Bool
    var modelCount: Int
    var apiKeyConfigured: Bool
    var apiKeySource: String
    var apiKeyResolved: Bool
    var apiKeyName: String

    init(
        id: String = "",
        baseUrl: String = "",
        apiKey: String = "",
        api: KajiAgentCustomProviderAPI = .openAIResponses,
        auth: KajiAgentCustomProviderAuth = .apiKey,
        discovery: KajiAgentCustomProviderDiscovery = .none,
        azureResourceGroup: String = "",
        azureAccountName: String = "",
        azureSubscription: String = "",
        headersText: String = "",
        disableStrictTools: Bool = false,
        models: [KajiAgentCustomProviderModel] = [KajiAgentCustomProviderModel()],
        isOverrideOnly: Bool = false,
        modelCount: Int = 0,
        apiKeyConfigured: Bool = false,
        apiKeySource: String = "none",
        apiKeyResolved: Bool = false,
        apiKeyName: String = ""
    ) {
        self.id = id
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.api = api
        self.auth = auth
        self.discovery = discovery
        self.azureResourceGroup = azureResourceGroup
        self.azureAccountName = azureAccountName
        self.azureSubscription = azureSubscription
        self.headersText = headersText
        self.disableStrictTools = disableStrictTools
        self.models = models
        self.isOverrideOnly = isOverrideOnly
        self.modelCount = modelCount
        self.apiKeyConfigured = apiKeyConfigured
        self.apiKeySource = apiKeySource
        self.apiKeyResolved = apiKeyResolved
        self.apiKeyName = apiKeyName
    }

    init?(json: KajiAgentJSONValue) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue
        else { return nil }
        self.id = id
        baseUrl = object["baseUrl"]?.stringValue ?? ""
        apiKey = object["apiKey"]?.stringValue ?? ""
        api = KajiAgentCustomProviderAPI(rawValue: object["api"]?.stringValue ?? "") ?? .providerDefault
        auth = KajiAgentCustomProviderAuth(rawValue: object["auth"]?.stringValue ?? "") ?? .apiKey
        let discoveryObject = object["discovery"]?.objectValue ?? [:]
        discovery = KajiAgentCustomProviderDiscovery(rawValue: discoveryObject["type"]?.stringValue ?? "") ?? .none
        azureResourceGroup = discoveryObject["resourceGroup"]?.stringValue ?? ""
        azureAccountName = discoveryObject["accountName"]?.stringValue ?? ""
        azureSubscription = discoveryObject["subscription"]?.stringValue ?? ""
        headersText = Self.headersText(from: object["headers"]?.objectValue ?? [:])
        disableStrictTools = object["disableStrictTools"]?.boolValue ?? false
        models = object["models"]?.arrayValue?.map(KajiAgentCustomProviderModel.init(json:)) ?? []
        isOverrideOnly = object["isOverrideOnly"]?.boolValue ?? models.isEmpty
        modelCount = object["modelCount"]?.numberAsInt ?? models.count
        apiKeyConfigured = object["apiKeyConfigured"]?.boolValue ?? !apiKey.isEmpty
        apiKeySource = object["apiKeySource"]?.stringValue ?? (apiKeyConfigured ? "literal" : "none")
        apiKeyResolved = object["apiKeyResolved"]?.boolValue ?? apiKeyConfigured
        apiKeyName = object["apiKeyName"]?.stringValue ?? ""
    }

    var json: KajiAgentJSONValue {
        var object: [String: KajiAgentJSONValue] = [
            "id": .string(id.trimmed),
            "baseUrl": .string(baseUrl.trimmed),
            "auth": .string(auth.rawValue),
            "disableStrictTools": .bool(disableStrictTools),
        ]
        if api != .providerDefault {
            object["api"] = .string(api.rawValue)
        }
        if auth == .apiKey, !apiKey.trimmed.isEmpty {
            object["apiKey"] = .string(apiKey.trimmed)
        }
        if discovery != .none {
            object["discovery"] = discoveryJSON
        }
        let headers = Self.headers(from: headersText)
        if !headers.isEmpty {
            object["headers"] = .object(headers.mapValues(KajiAgentJSONValue.string))
        }
        let validModels = models.filter { !$0.modelID.trimmed.isEmpty }
        if !validModels.isEmpty {
            object["models"] = .array(validModels.map(\.json))
        }
        return .object(object)
    }

    var validationErrors: [String] {
        var errors: [String] = []
        let hasConfiguredModels = models.contains { !$0.modelID.trimmed.isEmpty }
        let hasProviderOverride = !baseUrl.trimmed.isEmpty || !Self.headers(from: headersText).isEmpty || disableStrictTools
        let providerID = id.trimmed
        if providerID.isEmpty {
            errors.append("Provider ID is required.")
        }
        if !providerID.isEmpty, providerID.first?.isLetter != true, providerID.first?.isNumber != true {
            errors.append("Provider ID must start with a letter or number.")
        }
        if !providerID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) {
            errors.append("Provider ID can use letters, numbers, dots, hyphens, and underscores.")
        }
        if hasConfiguredModels, baseUrl.trimmed.isEmpty {
            errors.append("Base URL is required when adding manual models.")
        }
        if auth == .apiKey, apiKey.trimmed.isEmpty, !apiKeyConfigured, hasConfiguredModels || discovery != .none {
            errors.append("API key env var or token is required for API key auth.")
        }
        if api == .providerDefault, discovery != .proxy, hasConfiguredModels || discovery != .none {
            errors.append("Choose an API transport for custom models or discovery.")
        }
        if discovery == .azureOpenAIDeployments, api != .azureOpenAIResponses {
            errors.append("Azure deployment discovery requires Azure OpenAI Responses API.")
        }
        if discovery == .none, !hasConfiguredModels, !hasProviderOverride {
            errors.append("Add a model, choose discovery, or set a provider override.")
        }
        if models.contains(where: { !$0.isValid }) {
            errors.append("Each model needs an ID, at least one input type, and positive token values.")
        }
        return errors
    }

    var canSave: Bool { validationErrors.isEmpty }

    var canAutoMatchModels: Bool {
        discovery == .azureOpenAIDeployments
            && api == .azureOpenAIResponses
            && !id.trimmed.isEmpty
            && !baseUrl.trimmed.isEmpty
    }

    var canValidateConnection: Bool {
        api == .azureOpenAIResponses
            && !id.trimmed.isEmpty
            && !baseUrl.trimmed.isEmpty
            && (apiKeyConfigured || !apiKey.trimmed.isEmpty)
            && (discovery == .azureOpenAIDeployments || models.contains { !$0.modelID.trimmed.isEmpty })
    }

    private var discoveryJSON: KajiAgentJSONValue {
        var object: [String: KajiAgentJSONValue] = ["type": .string(discovery.rawValue)]
        if !azureResourceGroup.trimmed.isEmpty {
            object["resourceGroup"] = .string(azureResourceGroup.trimmed)
        }
        if !azureAccountName.trimmed.isEmpty {
            object["accountName"] = .string(azureAccountName.trimmed)
        }
        if !azureSubscription.trimmed.isEmpty {
            object["subscription"] = .string(azureSubscription.trimmed)
        }
        return .object(object)
    }

    private static func headersText(from object: [String: KajiAgentJSONValue]) -> String {
        object.compactMap { key, value in
            value.stringValue.map { "\(key): \($0)" }
        }
        .sorted()
        .joined(separator: "\n")
    }

    private static func headers(from text: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmed
            let value = String(parts[1]).trimmed
            if !key.isEmpty, !value.isEmpty {
                headers[key] = value
            }
        }
        return headers
    }
}

struct KajiAgentCustomProvidersState: Hashable {
    var path = "~/.omp/agent/models.yml"
    var providers: [KajiAgentCustomProvider] = []

    init(json: KajiAgentJSONValue?) {
        let object = json?.objectValue ?? [:]
        path = object["path"]?.stringValue ?? path
        providers = object["providers"]?.arrayValue?.compactMap(KajiAgentCustomProvider.init(json:)) ?? []
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

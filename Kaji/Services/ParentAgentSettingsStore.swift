import Foundation

@MainActor
@Observable
final class ParentAgentSettingsStore {
    static let shared = ParentAgentSettingsStore()
    static let providerIDKey = "kaji.parentAgent.providerID"
    static let modelIDKey = "kaji.parentAgent.modelID"
    static let thinkingLevelKey = "kaji.parentAgent.thinkingLevel"
    static let enabledKey = "kaji.parentAgent.enabled"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var providerID: String {
        didSet {
            normalizeModelForProvider()
            UserDefaults.standard.set(providerID, forKey: Self.providerIDKey)
        }
    }

    var modelID: String {
        didSet { UserDefaults.standard.set(modelID, forKey: Self.modelIDKey) }
    }

    var thinkingLevel: String {
        didSet { UserDefaults.standard.set(thinkingLevel, forKey: Self.thinkingLevelKey) }
    }

    private var authStatusVersion = 0

    private init() {
        let storedProviderID = UserDefaults.standard.string(forKey: Self.providerIDKey)
            ?? ParentAgentProviderRegistry.defaultProviderID
        providerID = storedProviderID
        modelID = UserDefaults.standard.string(forKey: Self.modelIDKey)
            ?? ParentAgentProviderRegistry.provider(id: storedProviderID).defaultModel
        thinkingLevel = UserDefaults.standard.string(forKey: Self.thinkingLevelKey)
            ?? ParentAgentThinkingLevel.off.rawValue
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        normalizeModelForProvider()
    }

    var provider: ParentAgentProvider {
        ParentAgentProviderRegistry.provider(id: providerID)
    }

    var modelOptions: [String] {
        ParentAgentProviderRegistry.modelOptions(for: providerID)
    }

    var selectedThinkingLevel: ParentAgentThinkingLevel {
        ParentAgentThinkingLevel(rawValue: thinkingLevel) ?? .off
    }

    var thinkingSupported: Bool {
        provider.supportsThinking
    }

    var readiness: ParentAgentReadiness {
        guard isEnabled else { return .disabled }
        guard ParentAgentRuntimeLocator.nodeExecutablePath() != nil else { return .missingNode }
        guard ParentAgentRuntimeLocator.sourceLaunch() != nil || ParentAgentRuntimeLocator.bundledScriptURL() != nil else {
            return .missingRuntime
        }
        return .ready
    }

    var authStatus: ParentAgentAuthStatus {
        _ = authStatusVersion
        let environment = ProcessInfo.processInfo.environment
        if let key = provider.environmentKeys.first(where: { environment[$0]?.isEmpty == false }) {
            return ParentAgentAuthStatus(configured: true, label: "Environment: \(key)")
        }
        if let oauthKey = provider.oauthKey, PiAuthFileReader.hasOAuthCredential(for: oauthKey) {
            return ParentAgentAuthStatus(configured: true, label: "OAuth: Pi auth file")
        }
        if PiAuthFileReader.credential(for: provider.authKey) != nil {
            return ParentAgentAuthStatus(configured: true, label: "Pi auth file")
        }
        if provider.oauthKey != nil {
            return ParentAgentAuthStatus(configured: false, label: "OAuth or API key required")
        }
        return ParentAgentAuthStatus(configured: false, label: "Missing \(provider.environmentKeys.joined(separator: " or "))")
    }

    func refreshAuthStatus() {
        authStatusVersion += 1
    }

    func launchEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "NODE_TLS_REJECT_UNAUTHORIZED")
        environment["KAJI_PARENT_PROVIDER"] = provider.id
        environment["KAJI_PARENT_MODEL"] = modelID
        environment["KAJI_PARENT_THINKING"] = thinkingSupported ? selectedThinkingLevel.environmentValue : "off"
        if let credential = PiAuthFileReader.credential(for: provider.authKey),
           let key = provider.environmentKeys.last
        {
            environment[key] = credential
        }
        return environment
    }

    private func normalizeModelForProvider() {
        let selectedProvider = ParentAgentProviderRegistry.provider(id: providerID)
        if !selectedProvider.models.contains(modelID) {
            modelID = selectedProvider.defaultModel
        }
    }
}

struct ParentAgentAuthStatus: Hashable {
    let configured: Bool
    let label: String
}

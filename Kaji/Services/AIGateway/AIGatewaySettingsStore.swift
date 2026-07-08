import Foundation
import os

private let aiGatewaySettingsLogger = Logger(subsystem: "app.kaji", category: "AIGatewaySettings")

@MainActor
@Observable
final class AIGatewaySettingsStore {
    static let shared = AIGatewaySettingsStore()

    private(set) var settings: AIGatewaySettings
    private(set) var token: String

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let credentialStore: AIGatewayCredentialStoreProtocol

    init(
        fileURL: URL = KajiFileStorage.fileURL(filename: "ai-gateway-settings.json"),
        credentialStore: AIGatewayCredentialStoreProtocol = AIGatewayCredentialStore.shared
    ) {
        self.fileURL = fileURL
        self.credentialStore = credentialStore
        self.settings = Self.loadSettings(fileURL: fileURL)
        self.token = ""
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        save()
    }

    func update(_ transform: (inout AIGatewaySettings) -> Void) {
        transform(&settings)
        settings.port = settings.normalizedPort
        AIGatewayModelAliasPolicy.sanitize(settings: &settings)
        save()
    }

    func updateProvider(_ provider: AIGatewayProviderConfiguration) {
        guard let index = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
        settings.providers[index] = provider
        AIGatewayModelAliasPolicy.sanitize(settings: &settings)
        save()
    }

    func saveProviderKey(_ key: String, providerID: String) {
        credentialStore.save(
            key.trimmingCharacters(in: .whitespacesAndNewlines),
            account: AIGatewayCredentialAccount.providerKey(providerID)
        )
    }

    func providerKeyStatus(providerID: String) -> Bool {
        !credentialStore.load(account: AIGatewayCredentialAccount.providerKey(providerID)).isEmpty
    }

    func rotateToken() {
        token = AIGatewayTokenGenerator.generate()
        credentialStore.save(token, account: AIGatewayCredentialAccount.gatewayToken)
    }

    func ensureToken() -> String {
        guard token.isEmpty else { return token }
        let existing = credentialStore.load(account: AIGatewayCredentialAccount.gatewayToken)
        if !existing.isEmpty {
            token = existing
            return existing
        }
        token = AIGatewayTokenGenerator.generate()
        credentialStore.save(token, account: AIGatewayCredentialAccount.gatewayToken)
        return token
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            aiGatewaySettingsLogger.error("Failed to save AI Gateway settings: \(error.localizedDescription)")
        }
    }

    private static func loadSettings(fileURL: URL) -> AIGatewaySettings {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AIGatewaySettings.self, from: data)
        else { return .defaults }
        return mergedWithDefaults(decoded)
    }

    private static func mergedWithDefaults(_ decoded: AIGatewaySettings) -> AIGatewaySettings {
        var settings = decoded
        let defaultsByID = Dictionary(uniqueKeysWithValues: AIGatewayProviderCatalog.defaults.map { ($0.id, $0) })
        for index in settings.providers.indices {
            guard let defaultProvider = defaultsByID[settings.providers[index].id] else { continue }
            settings.providers[index].name = defaultProvider.name
            settings.providers[index].kind = defaultProvider.kind
        }
        let existing = Set(settings.providers.map(\.id))
        settings.providers.append(contentsOf: AIGatewayProviderCatalog.defaults.filter { !existing.contains($0.id) })
        if settings.port == 4000 { settings.port = AIGatewaySettings.defaults.port }
        if settings.models.isEmpty { settings.models = AIGatewaySettings.defaults.models }
        AIGatewayModelAliasPolicy.sanitize(settings: &settings)
        return settings
    }
}

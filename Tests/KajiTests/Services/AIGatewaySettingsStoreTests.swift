import Foundation
import Testing

@testable import Kaji

@Suite("AI Gateway settings store")
@MainActor
struct AIGatewaySettingsStoreTests {
    @Test("does not create gateway token on init")
    func doesNotCreateTokenOnInit() {
        let credentials = StoreGatewayCredentials()
        let store = AIGatewaySettingsStore(
            fileURL: temporarySettingsURL(),
            credentialStore: credentials
        )

        #expect(store.token.isEmpty)
        #expect(credentials.values.isEmpty)
        #expect(credentials.loadRequests.isEmpty)

        let token = store.ensureToken()

        #expect(!token.isEmpty)
        #expect(store.token == token)
        #expect(credentials.values[AIGatewayCredentialAccount.gatewayToken] == token)
        #expect(credentials.loadRequests == [AIGatewayCredentialAccount.gatewayToken])
    }

    @Test("ensure token keeps an existing token")
    func ensureTokenKeepsExistingToken() {
        let credentials = StoreGatewayCredentials(values: [
            AIGatewayCredentialAccount.gatewayToken: "existing-token",
        ])
        let store = AIGatewaySettingsStore(
            fileURL: temporarySettingsURL(),
            credentialStore: credentials
        )

        #expect(store.token.isEmpty)
        #expect(credentials.loadRequests.isEmpty)

        let token = store.ensureToken()

        #expect(token == "existing-token")
        #expect(credentials.values[AIGatewayCredentialAccount.gatewayToken] == "existing-token")
        #expect(credentials.loadRequests == [AIGatewayCredentialAccount.gatewayToken])
    }


    @Test("defaults to Claude Code Router endpoints")
    func defaultsToClaudeCodeRouterEndpoints() {
        #expect(AIGatewaySettings.defaults.openAIBaseURL == "http://localhost:5254/v1")
        #expect(AIGatewaySettings.defaults.anthropicBaseURL == "http://localhost:5254")
    }

    @Test("decodes settings with removed backend key")
    func decodesSettingsWithRemovedBackendKey() throws {
        let json = """
        {
          "isEnabled": false,
          "autoStart": true,
          "bindAddress": "127.0.0.1",
          "port": 5254,
          "backend": "native",
          "providers": [],
          "models": [],
          "claudeConnectorEnabled": true,
          "codexConnectorEnabled": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AIGatewaySettings.self, from: json)

        #expect(settings.endpointBaseURL == "http://localhost:5254")
    }

    @Test("uses 5254 as the default gateway port")
    func usesNewDefaultPort() {
        #expect(AIGatewaySettings.defaults.port == 5254)
        #expect(AIGatewaySettings.defaults.endpointBaseURL == "http://localhost:5254")
    }

    @Test("migrates the old 4000 default port to 5254")
    func migratesLegacyDefaultPort() throws {
        let url = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var settings = AIGatewaySettings.defaults
        settings.port = 4000
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: url)

        let store = AIGatewaySettingsStore(fileURL: url, credentialStore: StoreGatewayCredentials())

        #expect(store.settings.port == 5254)
        #expect(store.settings.endpointBaseURL == "http://localhost:5254")
    }

    private func temporarySettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("ai-gateway-settings.json")
    }
}

private final class StoreGatewayCredentials: AIGatewayCredentialStoreProtocol {
    var values: [String: String] = [:]
    var loadRequests: [String] = []

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func load(account: String) -> String {
        loadRequests.append(account)
        return values[account] ?? ""
    }
    func save(_ value: String, account: String) { values[account] = value }
    func delete(account: String) { values.removeValue(forKey: account) }
}

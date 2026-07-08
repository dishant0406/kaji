import Foundation
import Testing

@testable import Kaji

struct AIGatewayCredentialStoreTests {
    @Test
    func savesLoadsAndDeletesSecretsFromLocalFile() throws {
        let fileURL = makeFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = AIGatewayCredentialStore(fileURL: fileURL)

        store.save("  sk-openrouter  ", account: AIGatewayCredentialAccount.providerKey("openrouter"))

        #expect(store.load(account: AIGatewayCredentialAccount.providerKey("openrouter")) == "sk-openrouter")
        let savedPermissions = try filePermissions(fileURL)
        let savedDirectoryPermissions = try filePermissions(fileURL.deletingLastPathComponent())
        #expect(savedPermissions == 0o600)
        #expect(savedDirectoryPermissions == 0o700)

        store.delete(account: AIGatewayCredentialAccount.providerKey("openrouter"))

        #expect(store.load(account: AIGatewayCredentialAccount.providerKey("openrouter")) == "")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func emptySaveRemovesOnlyThatSecret() throws {
        let fileURL = makeFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = AIGatewayCredentialStore(fileURL: fileURL)
        let token = AIGatewayCredentialAccount.gatewayToken
        let provider = AIGatewayCredentialAccount.providerKey("azure")

        store.save("gateway-token", account: token)
        store.save("azure-key", account: provider)
        store.save("", account: provider)

        #expect(store.load(account: provider) == "")
        #expect(store.load(account: token) == "gateway-token")
        let data = try Data(contentsOf: fileURL)
        let values = try JSONDecoder().decode([String: String].self, from: data)
        #expect(values == [token: "gateway-token"])
        let remainingPermissions = try filePermissions(fileURL)
        let remainingDirectoryPermissions = try filePermissions(fileURL.deletingLastPathComponent())
        #expect(remainingPermissions == 0o600)
        #expect(remainingDirectoryPermissions == 0o700)
    }

    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("ai-gateway-secrets.json")
    }

    private func filePermissions(_ fileURL: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}

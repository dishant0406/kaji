import Foundation
import Testing
@testable import Kaji

struct ParentAgentCodingProviderCatalogTests {
    @Test
    @MainActor
    func providerAvailabilityFollowsCodingAgentSettings() {
        let settings = CLILauncherSettings(fileURL: tempFileURL(), syncProviderState: false)
        let integration = FakeCodingProvider(id: "claude", installed: true)

        #expect(!ParentAgentCodingProviderCatalog.providerIsAvailable(integration, provider: .claude, settings: settings))

        settings.setEnabled(true, for: "claude")

        #expect(ParentAgentCodingProviderCatalog.providerIsAvailable(integration, provider: .claude, settings: settings))
    }

    @Test
    @MainActor
    func providerAvailabilityRequiresInstalledCli() {
        let settings = CLILauncherSettings(fileURL: tempFileURL(), syncProviderState: false)
        let integration = FakeCodingProvider(id: "claude", installed: false)

        settings.setEnabled(true, for: "claude")

        #expect(!ParentAgentCodingProviderCatalog.providerIsAvailable(integration, provider: .claude, settings: settings))
    }

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}

private struct FakeCodingProvider: AIProviderIntegration {
    let id: String
    let installed: Bool
    let displayName = "Fake"
    let socketTypeKey = "fake"
    let iconName = "sparkles"
    let executableNames: [String] = []

    func isToolInstalled() -> Bool {
        installed
    }

    func install(hookClientPath: String) throws {}

    func uninstall() throws {}
}

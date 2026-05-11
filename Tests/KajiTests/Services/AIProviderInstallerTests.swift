import Testing

@testable import Kaji

struct AIProviderInstallerTests {
    @Test
    func installCommandsUseSupportedPackageManagers() throws {
        let codex = try #require(AIProviderInstaller.command(for: TestProvider(id: "codex")))
        let claude = try #require(AIProviderInstaller.command(for: TestProvider(id: "claude")))
        let opencode = try #require(AIProviderInstaller.command(for: TestProvider(id: "opencode")))

        #expect(codex.arguments.last == "npm install -g @openai/codex")
        #expect(claude.arguments.last == "npm install -g @anthropic-ai/claude-code")
        #expect(opencode.arguments.last == "curl -fsSL https://opencode.ai/install | bash")
    }

    @Test
    func unsupportedProviderHasNoInstallCommand() {
        #expect(AIProviderInstaller.command(for: TestProvider(id: "unknown")) == nil)
    }
}

private struct TestProvider: AIProviderIntegration {
    let id: String
    var displayName: String { id }
    var socketTypeKey: String { id }
    var iconName: String { id }
    var executableNames: [String] { [id] }
    func install(hookClientPath _: String) throws {}
    func uninstall() throws {}
}

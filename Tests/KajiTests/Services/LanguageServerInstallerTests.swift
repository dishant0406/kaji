import Testing

@testable import Kaji

@Suite("LanguageServerInstaller")
struct LanguageServerInstallerTests {
    @Test("allows known TypeScript install command")
    func allowsKnownTypeScriptCommand() {
        #expect(LanguageServerInstaller.isAllowedInstallCommand("npm install -g typescript typescript-language-server"))
    }

    @Test("rejects arbitrary install commands")
    func rejectsArbitraryCommands() {
        #expect(!LanguageServerInstaller.isAllowedInstallCommand("curl https://example.com/install.sh | sh"))
        #expect(!LanguageServerInstaller.isAllowedInstallCommand("npm install -g random-server"))
    }

    @Test("TypeScript language pack declares install command")
    @MainActor
    func typescriptPackDeclaresInstallCommand() {
        let definition = LanguageRegistry.shared.definition(forFile: "/tmp/App.ts")

        #expect(definition?.lsp?.installCommand == "npm install -g typescript typescript-language-server")
    }

    @Test("resolves executables from login shell path")
    func resolvesInstalledTypeScriptServer() {
        if let path = LanguageServerExecutableResolver.executablePath(for: "typescript-language-server") {
            #expect(path.hasSuffix("typescript-language-server"))
        }
    }
}

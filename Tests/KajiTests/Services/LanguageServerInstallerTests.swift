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

    @Test("sync policy skips files without LSP")
    @MainActor
    func syncPolicySkipsFilesWithoutLSP() {
        let store = TextBackingStore()
        store.loadFromText("print('hello')")

        #expect(!LanguageServerManager.shared.canSync(filePath: "/tmp/app.py", backingStore: store))
    }

    @Test("sync policy accepts small LSP documents")
    @MainActor
    func syncPolicyAcceptsSmallLSPDocuments() {
        let store = TextBackingStore()
        store.loadFromText("const value = 1")

        #expect(LanguageServerManager.shared.canSync(filePath: "/tmp/app.ts", backingStore: store))
    }

    @Test("sync policy skips oversized LSP documents")
    @MainActor
    func syncPolicySkipsOversizedLSPDocuments() {
        let store = TextBackingStore()
        store.loadFromText(String(
            repeating: "a",
            count: LanguageServerManager.maximumDocumentUTF16Length + 1
        ))

        #expect(!LanguageServerManager.shared.canSync(filePath: "/tmp/app.ts", backingStore: store))
    }
}

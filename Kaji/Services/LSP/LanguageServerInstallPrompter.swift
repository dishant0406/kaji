import Foundation

@MainActor
enum LanguageServerInstallPrompter {
    private static var promptedServerIDs: Set<String> = []

    static func promptIfNeeded(definition: LanguageDefinition, projectPath: String, retry: @escaping () -> Void) {
        guard let lsp = definition.lsp, promptedServerIDs.insert(lsp.serverID).inserted else { return }
        let message = "\(definition.name) language server is not installed"
        ToastState.shared.showAction(message: message, actionTitle: "Install", timeout: 15_000_000_000) {
            install(definition: definition, projectPath: projectPath, retry: retry)
        }
    }

    private static func install(definition: LanguageDefinition, projectPath _: String, retry: @escaping () -> Void) {
        ToastState.shared.show("Installing \(definition.name) language server...")
        Task { @MainActor in
            do {
                try await LanguageServerInstaller.install(definition: definition)
                ToastState.shared.show("Installed \(definition.name) language server")
                retry()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ToastState.shared.show("Language server install failed: \(message)")
            }
        }
    }
}

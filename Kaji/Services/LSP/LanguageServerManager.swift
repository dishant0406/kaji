import Foundation

@MainActor
@Observable
final class LanguageServerManager {
    static let shared = LanguageServerManager()

    private var clients: [String: LanguageServerClient] = [:]

    func didOpen(filePath: String, projectPath: String, text: String) {
        guard let definition = LanguageRegistry.shared.definition(forFile: filePath), definition.lsp != nil else { return }
        client(for: definition, projectPath: projectPath).didOpen(filePath: filePath, text: text)
    }

    func didSave(filePath: String, projectPath: String, text: String) {
        guard let definition = LanguageRegistry.shared.definition(forFile: filePath), definition.lsp != nil else { return }
        client(for: definition, projectPath: projectPath).didSave(filePath: filePath, text: text)
    }

    func didClose(filePath: String, projectPath: String) {
        guard let definition = LanguageRegistry.shared.definition(forFile: filePath), definition.lsp != nil else { return }
        let key = clientKey(for: definition, projectPath: projectPath)
        guard let client = clients[key] else { return }
        client.didClose(filePath: filePath)
        if !client.hasOpenDocuments {
            clients[key] = nil
        }
    }

    func didChange(filePath: String, projectPath: String, text: String) {
        guard let definition = LanguageRegistry.shared.definition(forFile: filePath), definition.lsp != nil else { return }
        client(for: definition, projectPath: projectPath).didChange(filePath: filePath, text: text)
    }

    func stopAll() {
        clients.values.forEach { $0.stop() }
        clients = [:]
    }

    private func client(for definition: LanguageDefinition, projectPath: String) -> LanguageServerClient {
        let key = clientKey(for: definition, projectPath: projectPath)
        if let client = clients[key] { return client }
        let client = LanguageServerClient(definition: definition, projectPath: projectPath)
        clients[key] = client
        return client
    }

    private func clientKey(for definition: LanguageDefinition, projectPath: String) -> String {
        "\(projectPath)::\(definition.id)"
    }
}

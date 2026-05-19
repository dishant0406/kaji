import Foundation

enum LanguageServerInstallerError: LocalizedError {
    case missingInstallCommand
    case unsupportedInstallCommand(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingInstallCommand:
            "Language pack does not define an install command."
        case let .unsupportedInstallCommand(command):
            "Unsupported language server install command: \(command)"
        case let .installFailed(message):
            message.isEmpty ? "Language server install failed." : message
        }
    }
}

enum LanguageServerInstaller {
    static func install(definition: LanguageDefinition) async throws {
        guard let command = definition.lsp?.installCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            throw LanguageServerInstallerError.missingInstallCommand
        }
        guard isAllowedInstallCommand(command) else {
            throw LanguageServerInstallerError.unsupportedInstallCommand(command)
        }
        let result = try await GitProcessRunner.runCommand(
            executable: "/bin/zsh",
            arguments: ["-lc", command],
            workingDirectory: NSHomeDirectory()
        )
        guard result.status == 0 else {
            throw LanguageServerInstallerError.installFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func isAllowedInstallCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "npm install -g typescript typescript-language-server"
    }
}

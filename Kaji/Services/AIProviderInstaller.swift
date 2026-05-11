import Foundation

enum AIProviderInstaller {
    struct InstallCommand: Hashable {
        let executable: String
        let arguments: [String]
    }

    static func command(for provider: AIProviderIntegration) -> InstallCommand? {
        CodingAgentRegistry.shared.definition(id: provider.id)?.installCommand
    }

    static func install(_ provider: AIProviderIntegration) async -> Result<Void, Error> {
        guard let command = command(for: provider) else { return .failure(InstallError.unsupportedProvider) }
        return await install(command)
    }

    static func install(_ command: InstallCommand) async -> Result<Void, Error> {
        await GitProcessRunner.offMain {
            run(command)
        }
    }

    private static func run(_ command: InstallCommand) -> Result<Void, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .failure(InstallError.failed(status: process.terminationStatus)) }
        return .success(())
    }

    enum InstallError: LocalizedError, Equatable {
        case unsupportedProvider
        case failed(status: Int32)

        var errorDescription: String? {
            switch self {
            case .unsupportedProvider:
                "Provider install is not supported."
            case let .failed(status):
                "Install failed with status \(status)."
            }
        }
    }
}

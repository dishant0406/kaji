import Foundation

enum CLILauncherInstallStateResolver {
    static func isInstalled(for launcherID: String, command: String? = nil) async -> Bool {
        guard CodingAgentRegistry.shared.agent(id: launcherID) != nil else { return false }
        return await GitProcessRunner.offMain {
            if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CLILauncherCommandResolver.resolvedExecutableURL(in: command) != nil
            }
            return CodingAgentRegistry.shared.agent(id: launcherID)?.resolveExecutable(
                env: ProcessInfo.processInfo.environment,
                homeDirectory: NSHomeDirectory(),
                fileManager: .default,
                excluding: nil
            ) != nil
        }
    }

    static func isInstalled(
        executableNames: [String],
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        extraDirectories: [String] = []
    ) async -> Bool {
        await GitProcessRunner.offMain {
            AIProviderExecutableLocator.isInstalled(
                executableNames: executableNames,
                env: env,
                homeDirectory: homeDirectory,
                extraDirectories: extraDirectories
            )
        }
    }
}

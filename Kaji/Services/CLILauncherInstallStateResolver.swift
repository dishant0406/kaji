import Foundation

enum CLILauncherInstallStateResolver {
    static func isInstalled(for launcherID: String) async -> Bool {
        guard CodingAgentRegistry.shared.agent(id: launcherID) != nil else { return false }
        return await GitProcessRunner.offMain {
            CodingAgentRegistry.shared.agent(id: launcherID)?.resolveExecutable(
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

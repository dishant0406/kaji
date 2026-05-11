import Foundation

enum CLILauncherInstallStateResolver {
    static func isInstalled(for launcherID: String) async -> Bool {
        guard let definition = CodingAgentRegistry.shared.definition(id: launcherID) else { return false }
        return await isInstalled(
            executableNames: definition.executableNames,
            extraDirectories: definition.executableSearchDirectories
        )
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

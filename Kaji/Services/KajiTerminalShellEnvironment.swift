import Foundation

@MainActor
enum KajiTerminalShellEnvironment {
    static func variables(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        browserEnabled: Bool = BrowserExtensionPreferences.isEnabled
    ) -> [(key: String, value: String)] {
        if !browserEnabled {
            KajiBrowserSessionEnvironmentStore.remove(homeDirectory: homeDirectory, fileManager: fileManager)
        }

        return KajiShellBootstrapInstaller.install(
            homeDirectory: homeDirectory,
            userZdotdir: environment[KajiShellBootstrapInstaller.zdotdirKey],
            fileManager: fileManager
        )
    }
}

import Foundation

enum KajiCodeCommandBuilder {
    static func splitCommand(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> String {
        KajiCodeRuntimeLocator.launchCommand(env: env, homeDirectory: homeDirectory, fileManager: fileManager)
    }
}

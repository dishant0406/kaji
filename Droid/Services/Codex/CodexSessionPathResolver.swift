import Foundation

enum CodexSessionPathResolver {
    static func sessionsRootURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        URL(fileURLWithPath: CodexProvider.configPath(env: env))
            .deletingLastPathComponent()
            .appendingPathComponent("sessions", isDirectory: true)
    }
}

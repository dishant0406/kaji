import Foundation

enum AIGatewayClaudeCodeRouterStateCleaner {
    static func removePersistedConfig(
        configDirectory: URL = AIGatewayClaudeCodeRouterPaths.configDirectory(),
        fileManager: FileManager = .default
    ) throws {
        for url in stateURLs(configDirectory: configDirectory) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static func stateURLs(configDirectory: URL = AIGatewayClaudeCodeRouterPaths.configDirectory()) -> [URL] {
        [
            "config.sqlite",
            "config.sqlite-shm",
            "config.sqlite-wal",
        ].map { configDirectory.appendingPathComponent($0) }
    }
}

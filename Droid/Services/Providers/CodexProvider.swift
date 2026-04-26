import Foundation

struct CodexProvider: AIProviderIntegration, AIUsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let socketTypeKey = "codex"
    let iconName = "codex"
    let executableNames = ["codex"]

    private static let configFileName = "config.toml"

    func install(hookScriptPath: String) throws {
        let scriptPath = DroidNotificationHooks.scriptPath(named: "droid-codex-notify", extension: "sh") ?? hookScriptPath
        let content = try Self.readConfig()
        let updated = CodexNotificationConfig.install(in: content, scriptPath: scriptPath)
        try Self.writeConfig(updated)
    }

    func uninstall() throws {
        let path = Self.configPath()
        guard FileManager.default.fileExists(atPath: path) else { return }
        let content = try Self.readConfig()
        let updated = CodexNotificationConfig.uninstall(from: content)
        try Self.writeConfig(updated)
    }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        await CodexUsageProvider().fetchUsageSnapshot()
    }

    static func configPath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let basePath = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let basePath, !basePath.isEmpty {
            return (basePath as NSString).appendingPathComponent(configFileName)
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".codex/\(configFileName)")
    }

    private static func readConfig(env: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let path = configPath(env: env)
        guard FileManager.default.fileExists(atPath: path) else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func writeConfig(_ content: String, env: [String: String] = ProcessInfo.processInfo.environment) throws {
        let path = configPath(env: env)
        let dirPath = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        let fileURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            let backupURL = URL(fileURLWithPath: path + ".droid-backup")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        }

        let normalized = content.isEmpty ? "" : content
        try normalized.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}

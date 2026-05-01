import Foundation

struct CodexProvider: AIProviderIntegration, AIUsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let socketTypeKey = "codex"
    let iconName = "codex"
    let executableNames = ["codex"]

    private static let configFileName = "config.toml"
    private static let hooksFileName = "hooks.json"

    func install(hookClientPath: String) throws {
        let config = try Self.readConfig()
        let hooks = try Self.readHooks()
        let notifyRemoved = CodexNotificationConfig.uninstall(from: config)
        let installed = CodexHooksConfig.install(
            config: notifyRemoved,
            hooksContent: hooks,
            hookClientPath: hookClientPath
        )
        try Self.writeConfig(installed.config)
        try Self.writeHooks(installed.hooks)
    }

    func uninstall() throws {
        let configPath = Self.configPath()
        if FileManager.default.fileExists(atPath: configPath) {
            let content = try Self.readConfig()
            let updated = CodexNotificationConfig.uninstall(from: content)
            try Self.writeConfig(updated)
        }

        let hooksPath = Self.hooksPath()
        guard FileManager.default.fileExists(atPath: hooksPath) else { return }
        let hooks = try Self.readHooks()
        let updatedHooks = CodexHooksConfig.uninstall(from: hooks)
        if updatedHooks.isEmpty {
            try FileManager.default.removeItem(atPath: hooksPath)
            return
        }
        try Self.writeHooks(updatedHooks)
    }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        await CodexUsageProvider().fetchUsageSnapshot()
    }

    static func configPath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        basePath(env: env).appendingPathComponent(configFileName)
    }

    static func hooksPath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        basePath(env: env).appendingPathComponent(hooksFileName)
    }

    private static func basePath(env: [String: String]) -> NSString {
        let basePath = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let basePath, !basePath.isEmpty {
            return basePath as NSString
        }
        return ((NSHomeDirectory() as NSString).appendingPathComponent(".codex")) as NSString
    }

    private static func readConfig(env: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let path = configPath(env: env)
        guard FileManager.default.fileExists(atPath: path) else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func readHooks(env: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let path = hooksPath(env: env)
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

    private static func writeHooks(_ content: String, env: [String: String] = ProcessInfo.processInfo.environment) throws {
        let path = hooksPath(env: env)
        let dirPath = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        let fileURL = URL(fileURLWithPath: path)
        let normalized = content.isEmpty ? "{}\n" : content
        try normalized.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}

import Foundation

struct OpenCodeProvider: AIProviderIntegration {
    let id = "opencode"
    let displayName = "OpenCode"
    let socketTypeKey = "opencode"
    let iconName = "opencode"
    let executableNames = ["opencode"]

    private static let pluginFileName = "droid-notify.js"
    private static let pluginScriptName = "opencode-droid-plugin.js"
    private static let obsoletePluginNames = ["muxy-notify.js"]

    func install(hookClientPath: String) throws {
        try install(
            hookClientPath: hookClientPath,
            homeDirectory: NSHomeDirectory(),
            fileManager: .default
        )
    }

    func install(
        hookClientPath: String,
        homeDirectory: String,
        fileManager: FileManager
    ) throws {
        guard let sourcePlugin = Self.findPluginSource(near: hookClientPath) else { return }
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePlugin))
        try removeObsoletePlugins(homeDirectory: homeDirectory, fileManager: fileManager)

        let pluginPaths = Self.pluginPaths(homeDirectory: homeDirectory)
        for pluginPath in pluginPaths {
            if fileManager.fileExists(atPath: pluginPath),
               let existingData = try? Data(contentsOf: URL(fileURLWithPath: pluginPath)),
               existingData == sourceData
            {
                continue
            }

            let pluginsDir = (pluginPath as NSString).deletingLastPathComponent
            try fileManager.createDirectory(atPath: pluginsDir, withIntermediateDirectories: true)
            let dest = URL(fileURLWithPath: pluginPath)
            if fileManager.fileExists(atPath: pluginPath) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: URL(fileURLWithPath: sourcePlugin), to: dest)
        }

        try ensureConfigReferencesPlugin(
            pluginPath: pluginPaths[0],
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
    }

    func uninstall() throws {
        let allPaths = Self.pluginPaths() + Self.obsoletePluginPaths()
        for pluginPath in allPaths where FileManager.default.fileExists(atPath: pluginPath) {
            try FileManager.default.removeItem(atPath: pluginPath)
        }
        try removeConfigReference(homeDirectory: NSHomeDirectory(), fileManager: .default)
    }

    private static func findPluginSource(near hookClientPath: String) -> String? {
        if let bundled = DroidNotificationHooks.scriptPath(named: "opencode-droid-plugin", extension: "js") {
            return bundled
        }

        let hookDir = (hookClientPath as NSString).deletingLastPathComponent
        let candidate = (hookDir as NSString).appendingPathComponent(pluginScriptName)
        guard FileManager.default.fileExists(atPath: candidate) else { return nil }
        return candidate
    }

    static func pluginPaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "\(homeDirectory)/.config/opencode/plugins/\(pluginFileName)",
            "\(homeDirectory)/.opencode/plugins/\(pluginFileName)",
        ]
    }

    private func removeObsoletePlugins(
        homeDirectory: String,
        fileManager: FileManager
    ) throws {
        for pluginPath in Self.obsoletePluginPaths(homeDirectory: homeDirectory)
            where fileManager.fileExists(atPath: pluginPath)
        {
            try fileManager.removeItem(atPath: pluginPath)
        }
    }

    private static func obsoletePluginPaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "\(homeDirectory)/.config/opencode/plugins",
            "\(homeDirectory)/.opencode/plugins",
        ].flatMap { directory in
            obsoletePluginNames.map { "\(directory)/\($0)" }
        }
    }

    private func ensureConfigReferencesPlugin(
        pluginPath: String,
        homeDirectory: String,
        fileManager: FileManager
    ) throws {
        let configPath = Self.configPath(homeDirectory: homeDirectory)
        var config = try Self.loadConfig(path: configPath, fileManager: fileManager)
        let pluginURL = URL(fileURLWithPath: pluginPath).absoluteString
        var plugins = config["plugin"] as? [String] ?? []
        guard !plugins.contains(pluginURL) else { return }

        plugins.append(pluginURL)
        config["plugin"] = plugins
        try Self.saveConfig(config, path: configPath, fileManager: fileManager)
    }

    private func removeConfigReference(
        homeDirectory: String,
        fileManager: FileManager
    ) throws {
        let configPath = Self.configPath(homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: configPath) else { return }

        var config = try Self.loadConfig(path: configPath, fileManager: fileManager)
        let pluginURLs = Self.pluginPaths(homeDirectory: homeDirectory)
            .map { URL(fileURLWithPath: $0).absoluteString }
        let plugins = (config["plugin"] as? [String] ?? []).filter { !pluginURLs.contains($0) }
        config["plugin"] = plugins
        try Self.saveConfig(config, path: configPath, fileManager: fileManager)
    }

    static func configPath(homeDirectory: String = NSHomeDirectory()) -> String {
        "\(homeDirectory)/.config/opencode/opencode.json"
    }

    private static func loadConfig(
        path: String,
        fileManager: FileManager
    ) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: path) else {
            return ["$schema": "https://opencode.ai/config.json"]
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let object = try JSONSerialization.jsonObject(with: data)
        guard let config = object as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return config
    }

    private static func saveConfig(
        _ config: [String: Any],
        path: String,
        fileManager: FileManager
    ) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

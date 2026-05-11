import Foundation

struct OpenCodeAgentModule: CodingAgentModule {
    let socketTypeKey = "opencode"
    let mcpServerConfigProvider: MCPServerConfigProvider? = OpenCodeMCPServerConfigProvider()

    let definition = CodingAgentDefinition(
        id: "opencode",
        displayName: "OpenCode",
        annotationValues: ["opencode"],
        iconName: "opencode",
        executableNames: ["opencode"],
        executableSearchDirectories: [".opencode/bin"],
        defaultCommand: "opencode",
        installCommand: .init(executable: "/bin/zsh", arguments: ["-lc", "curl -fsSL https://opencode.ai/install | bash"]),
        configDirectories: [".config/opencode", ".opencode"],
        dataDirectories: [".local/share/opencode"],
        hookStrategy: .bundledPlugin(scriptName: "CodingAgents/OpenCode/opencode-kaji-plugin.js"),
        historyStrategy: .sqlite(".local/share/opencode/opencode.db"),
        modelStrategy: .command(.init(executableName: "opencode", arguments: ["models"])),
        usageStrategy: .none,
        commandProfile: .init(
            prompt: .flag("--prompt"),
            modelFlag: "--model",
            resume: .flagWithPrompt(sessionFlag: "--session", promptFlag: "--prompt"),
            skillInvocation: .instructionTemplate("Use the {name} skill. Follow the instructions in {path}.")
        ),
        models: [],
        defaultModel: nil,
        modelListCommand: .init(executableName: "opencode", arguments: ["models"]),
        stopEscapeCount: 2,
        globalInstructionFiles: [".config/opencode/AGENTS.md", ".opencode/AGENTS.md"],
        projectInstructionFiles: ["AGENTS.md"],
        homeSkillDirectories: [],
        projectSkillDirectories: [".agents/skills"]
    )

    private static let pluginFileName = "kaji-notify.js"
    private static let pluginScriptName = "opencode-kaji-plugin.js"
    private static let obsoletePluginNames = ["muxy-notify.js"]

    func install(hookClientPath: String) throws {
        try install(hookClientPath: hookClientPath, homeDirectory: NSHomeDirectory(), fileManager: .default)
    }

    func historyOptions(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        OpenCodeAgentHistory.options(projectPath: projectPath, query: query, limit: limit, env: env, fileManager: fileManager)
    }

    func install(hookClientPath: String, homeDirectory: String, fileManager: FileManager) throws {
        guard let sourcePlugin = Self.findPluginSource(near: hookClientPath) else { return }
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePlugin))
        try removeObsoletePlugins(homeDirectory: homeDirectory, fileManager: fileManager)
        let pluginPaths = Self.pluginPaths(homeDirectory: homeDirectory)
        for pluginPath in pluginPaths {
            let existingData = try? Data(contentsOf: URL(fileURLWithPath: pluginPath))
            guard !fileManager.fileExists(atPath: pluginPath) || existingData != sourceData else { continue }
            try fileManager.createDirectory(
                atPath: (pluginPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: pluginPath) { try fileManager.removeItem(atPath: pluginPath) }
            try fileManager.copyItem(atPath: sourcePlugin, toPath: pluginPath)
        }
        try ensureConfigReferencesPlugin(pluginPath: pluginPaths[0], homeDirectory: homeDirectory, fileManager: fileManager)
    }

    func uninstall() throws {
        for pluginPath in Self.pluginPaths() + Self.obsoletePluginPaths() where FileManager.default.fileExists(atPath: pluginPath) {
            try FileManager.default.removeItem(atPath: pluginPath)
        }
        try removeConfigReference(homeDirectory: NSHomeDirectory(), fileManager: .default)
    }

    static func pluginPaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        ["\(homeDirectory)/.config/opencode/plugins/\(pluginFileName)", "\(homeDirectory)/.opencode/plugins/\(pluginFileName)"]
    }

    static func configPath(homeDirectory: String = NSHomeDirectory()) -> String {
        "\(homeDirectory)/.config/opencode/opencode.json"
    }

    private static func findPluginSource(near hookClientPath: String) -> String? {
        if let bundled = KajiNotificationHooks.scriptPath(
            named: "opencode-kaji-plugin",
            extension: "js",
            subdirectory: "CodingAgents/OpenCode"
        ) { return bundled }
        let candidate = ((hookClientPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(pluginScriptName)
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    private static func obsoletePluginPaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        ["\(homeDirectory)/.config/opencode/plugins", "\(homeDirectory)/.opencode/plugins"].flatMap { directory in
            obsoletePluginNames.map { "\(directory)/\($0)" }
        }
    }

    private func removeObsoletePlugins(homeDirectory: String, fileManager: FileManager) throws {
        for pluginPath in Self.obsoletePluginPaths(homeDirectory: homeDirectory) where fileManager.fileExists(atPath: pluginPath) {
            try fileManager.removeItem(atPath: pluginPath)
        }
    }

    private func ensureConfigReferencesPlugin(pluginPath: String, homeDirectory: String, fileManager: FileManager) throws {
        let configPath = Self.configPath(homeDirectory: homeDirectory)
        var config = try Self.loadConfig(path: configPath, fileManager: fileManager)
        let pluginURL = URL(fileURLWithPath: pluginPath).absoluteString
        var plugins = config["plugin"] as? [String] ?? []
        guard !plugins.contains(pluginURL) else { return }
        plugins.append(pluginURL)
        config["plugin"] = plugins
        try Self.saveConfig(config, path: configPath, fileManager: fileManager)
    }

    private func removeConfigReference(homeDirectory: String, fileManager: FileManager) throws {
        let configPath = Self.configPath(homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: configPath) else { return }
        var config = try Self.loadConfig(path: configPath, fileManager: fileManager)
        let pluginURLs = Self.pluginPaths(homeDirectory: homeDirectory).map { URL(fileURLWithPath: $0).absoluteString }
        config["plugin"] = (config["plugin"] as? [String] ?? []).filter { !pluginURLs.contains($0) }
        try Self.saveConfig(config, path: configPath, fileManager: fileManager)
    }

    private static func loadConfig(path: String, fileManager: FileManager) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: path) else { return ["$schema": "https://opencode.ai/config.json"] }
        guard let config = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: path))
        ) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        return config
    }

    private static func saveConfig(_ config: [String: Any], path: String, fileManager: FileManager) throws {
        try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

typealias OpenCodeProvider = OpenCodeAgentModule

import Foundation

struct CodexAgentModule: CodingAgentModule, AIUsageProvider {
    let socketTypeKey = "codex"
    let mcpServerConfigProvider: MCPServerConfigProvider? = CodexMCPServerConfigProvider()

    let definition = CodingAgentDefinition(
        id: "codex",
        displayName: "Codex",
        annotationValues: ["codex"],
        iconName: "codex",
        executableNames: ["codex"],
        executableSearchDirectories: [],
        defaultCommand: "codex",
        installCommand: .init(executable: "/bin/zsh", arguments: ["-lc", "npm install -g @openai/codex"]),
        configDirectories: [".codex"],
        dataDirectories: [".codex/sessions"],
        hookStrategy: .sessionMonitor("Codex hooks emit activity; completions are read from session JSONL"),
        historyStrategy: .jsonlFiles(".codex/sessions"),
        modelStrategy: .staticList,
        usageStrategy: .localAuthFile(".codex/auth.json"),
        commandProfile: .init(
            prompt: .positional,
            modelFlag: "--model",
            resume: .subcommandWithPromptFlag(command: "resume", promptFlag: "--"),
            skillInvocation: .instructionTemplate("Use the {name} skill. Follow the instructions in {path}.")
        ),
        models: ["gpt-5.5", "gpt-5.4", "gpt-5.2-codex", "gpt-5.1-codex", "gpt-5-codex"],
        defaultModel: "gpt-5.5",
        modelListCommand: nil,
        stopEscapeCount: 1,
        globalInstructionFiles: [".codex/AGENTS.md", ".codex/AGENTS.override.md", ".agents/AGENTS.md"],
        projectInstructionFiles: ["AGENTS.md", "AGENTS.override.md"],
        homeSkillDirectories: [".codex/skills"],
        projectSkillDirectories: [".agents/skills"],
        notificationPolicy: .init(coalesceGenericCompletions: true)
    )

    private static let configFileName = "config.toml"
    private static let hooksFileName = "hooks.json"

    func install(hookClientPath: String) throws {
        let config = try Self.readConfig()
        let hooks = try Self.readHooks()
        let notifyRemoved = CodexNotificationConfig.uninstall(from: config)
        let installed = CodexHooksConfig.install(config: notifyRemoved, hooksContent: hooks, hookClientPath: hookClientPath)
        try Self.writeConfig(installed.config)
        try Self.writeHooks(installed.hooks)
    }

    func uninstall() throws {
        let configPath = Self.configPath()
        if FileManager.default.fileExists(atPath: configPath) {
            let content = try Self.readConfig()
            try Self.writeConfig(CodexNotificationConfig.uninstall(from: content))
        }
        let hooksPath = Self.hooksPath()
        guard FileManager.default.fileExists(atPath: hooksPath) else { return }
        let updatedHooks = try CodexHooksConfig.uninstall(from: Self.readHooks())
        if updatedHooks.isEmpty {
            try FileManager.default.removeItem(atPath: hooksPath)
            return
        }
        try Self.writeHooks(updatedHooks)
    }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        await CodexUsageProvider().fetchUsageSnapshot()
    }

    func historyOptions(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        CodexAgentHistory.options(projectPath: projectPath, query: query, limit: limit, env: env, fileManager: fileManager)
    }

    func modelOptions(projectPath: String?) -> [String] {
        Self.modelOptions(env: ProcessInfo.processInfo.environment, fallbackModels: definition.models)
    }

    static func modelOptions(env: [String: String], fallbackModels: [String]) -> [String] {
        let configured = configuredDefaultModel(env: env)
        guard let configured, !fallbackModels.contains(configured) else { return fallbackModels }
        return [configured] + fallbackModels
    }

    func defaultModel(projectPath: String?) -> String? {
        Self.configuredDefaultModel() ?? definition.defaultModel
    }

    static func configPath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        basePath(env: env).appendingPathComponent(configFileName)
    }

    static func hooksPath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        basePath(env: env).appendingPathComponent(hooksFileName)
    }

    private static func basePath(env: [String: String]) -> NSString {
        let basePath = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let basePath, !basePath.isEmpty else {
            return "\(NSHomeDirectory())/.codex" as NSString
        }
        return basePath as NSString
    }

    private static func readConfig(env: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let path = configPath(env: env)
        guard FileManager.default.fileExists(atPath: path) else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    static func configuredDefaultModel(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        let path = configPath(env: env)
        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        return modelValue(from: content)
    }

    private static func modelValue(from content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let value = parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func readHooks(env: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        let path = hooksPath(env: env)
        guard FileManager.default.fileExists(atPath: path) else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func writeConfig(_ content: String, env: [String: String] = ProcessInfo.processInfo.environment) throws {
        try write(content, to: configPath(env: env), emptyContent: "")
    }

    private static func writeHooks(_ content: String, env: [String: String] = ProcessInfo.processInfo.environment) throws {
        try write(content, to: hooksPath(env: env), emptyContent: "{}\n")
    }

    private static func write(_ content: String, to path: String, emptyContent: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try (content.isEmpty ? emptyContent : content).data(using: .utf8)?.write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}

typealias CodexProvider = CodexAgentModule

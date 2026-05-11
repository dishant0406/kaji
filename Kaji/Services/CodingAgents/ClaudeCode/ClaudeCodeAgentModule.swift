import Foundation

struct ClaudeCodeAgentModule: CodingAgentModule, AIUsageProvider {
    let socketTypeKey = "claude_hook"
    let mcpServerConfigProvider: MCPServerConfigProvider? = ClaudeMCPServerConfigProvider()

    let definition = CodingAgentDefinition(
        id: "claude",
        displayName: "Claude Code",
        annotationValues: ["claude", "claude-code", "claudecode"],
        iconName: "claude",
        executableNames: ["claude", "claude-code"],
        executableSearchDirectories: [".local/bin"],
        defaultCommand: "claude",
        installCommand: .init(executable: "/bin/zsh", arguments: ["-lc", "npm install -g @anthropic-ai/claude-code"]),
        configDirectories: [".claude"],
        dataDirectories: [".claude/projects"],
        hookStrategy: .nativeConfig(".claude/settings.json hooks"),
        historyStrategy: .jsonlFiles(".claude/projects"),
        modelStrategy: .staticList,
        usageStrategy: .providerAPI("Anthropic OAuth usage API"),
        commandProfile: .init(
            prompt: .positional,
            modelFlag: "--model",
            resume: .flag("--resume"),
            skillInvocation: .slashCommand(prefix: "/")
        ),
        models: ["sonnet", "opus", "haiku", "claude-sonnet-4-6", "claude-opus-4-7", "claude-haiku-4-5"],
        defaultModel: "sonnet",
        modelListCommand: nil,
        stopEscapeCount: 1,
        globalInstructionFiles: [".claude/CLAUDE.md", ".claude/AGENTS.md"],
        projectInstructionFiles: ["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md"],
        homeSkillDirectories: [".claude/skills"],
        projectSkillDirectories: [".claude/skills", ".agents/skills"]
    )

    private static let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
    private static let kajiMarker = "kaji-notification-hook"
    private static let obsoleteMarkers = [kajiMarker, "muxy-notification-hook"]
    private static let credentialsKeychainService = "Claude Code-credentials"
    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")

    func isToolInstalled() -> Bool {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude"].contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    func install(hookClientPath: String) throws {
        let commands = [
            "Notification": hookCommand(hookClientPath: hookClientPath, event: "notification"),
            "PermissionRequest": hookCommand(hookClientPath: hookClientPath, event: "permissionrequest"),
            "SessionStart": hookCommand(hookClientPath: hookClientPath, event: "sessionstart"),
            "Stop": hookCommand(hookClientPath: hookClientPath, event: "stop"),
            "UserPromptSubmit": hookCommand(hookClientPath: hookClientPath, event: "userpromptsubmit"),
        ]
        var settings = try Self.readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        guard !commands.allSatisfy({ key, command in
            Self.kajiHookMatches(entries: hooks[key] as? [[String: Any]], expectedCommand: command)
        })
        else { return }
        for (key, command) in commands {
            hooks[key] = Self.mergeHookArray(
                existing: hooks[key] as? [[String: Any]],
                kajiHook: Self.buildHookEntry(command: command, matcher: key == "PermissionRequest" ? "*" : "")
            )
        }
        settings["hooks"] = hooks
        try Self.writeSettings(settings)
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: Self.settingsPath) else { return }
        var settings = try Self.readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for key in ["Notification", "PermissionRequest", "SessionStart", "Stop", "UserPromptSubmit"] {
            guard var entries = hooks[key] as? [[String: Any]] else { continue }
            entries.removeAll { Self.isKajiHookEntry($0) }
            hooks[key] = entries.isEmpty ? nil : entries
        }
        settings["hooks"] = hooks
        try Self.writeSettings(settings)
    }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        await AIUsageSession.fetchSnapshot(
            provider: self,
            messages: AIUsageSessionMessages(
                missingCredentials: "Sign in to Claude",
                unauthenticated: "Sign in to Claude"
            ),
            buildRequest: buildUsageRequest,
            parse: ClaudeUsageParser.parseMetricRows(from:)
        )
    }

    func historyOptions(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        ClaudeCodeAgentHistory.options(projectPath: projectPath, query: query, limit: limit, env: env, fileManager: fileManager)
    }

    func modelOptions(projectPath: String?) -> [String] {
        let configured = Self.configuredModels(projectPath: projectPath)
        return configured.isEmpty ? definition.models : configured
    }

    private func hookCommand(hookClientPath: String, event: String) -> String {
        "\(ShellEscaper.escape(hookClientPath)) claude-hook \(event) # \(Self.kajiMarker)"
    }

    private func buildUsageRequest() throws -> URLRequest {
        guard let endpoint = Self.usageEndpoint else { throw AIUsageAuthError.missingCredentials }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        try request.setValue("Bearer \(readAccessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return request
    }

    private func readAccessToken() throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let token = AIUsageTokenReader.fromEnvironment(keys: ["CLAUDE_CODE_OAUTH_TOKEN"], env: env) { return token }
        if let token = try AIUsageTokenReader.fromJSONFile(
            path: Self.credentialsFilePath(env: env),
            nestedKeyPath: ["claudeAiOauth"],
            valueKeys: ["accessToken"]
        ), !token.isEmpty {
            return token
        }
        let account = env["USER"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = Self.keychainAccessToken(account: account) { return token }
        throw AIUsageAuthError.missingCredentials
    }

    private static func keychainAccessToken(account: String?) -> String? {
        guard let raw = AIUsageTokenReader.fromKeychain(service: credentialsKeychainService, account: account),
              let data = raw.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = payload["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return AIUsageParserSupport.string(in: oauth, keys: ["accessToken"])
    }

    private static func credentialsFilePath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let base = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "\(NSHomeDirectory())/.claude"
        return "\(base)/.credentials.json"
    }

    static func configuredModels(
        projectPath: String?,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [String] {
        for path in settingsPaths(projectPath: projectPath, env: env) {
            guard let models = availableModels(path: path, fileManager: fileManager), !models.isEmpty else { continue }
            return models
        }
        return []
    }

    private static func settingsPaths(projectPath: String?, env: [String: String]) -> [String] {
        let home = env["HOME"] ?? NSHomeDirectory()
        let userConfig = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "\(home)/.claude"
        return [
            projectPath.map { "\($0)/.claude/settings.local.json" },
            projectPath.map { "\($0)/.claude/settings.json" },
            "\(userConfig)/settings.json",
        ].compactMap(\.self)
    }

    private static func availableModels(path: String, fileManager: FileManager) -> [String]? {
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (object["availableModels"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func buildHookEntry(command: String, matcher: String) -> [String: Any] {
        ["matcher": matcher, "hooks": [["type": "command", "command": command, "timeout": 10] as [String: Any]]]
    }

    private static func kajiHookMatches(entries: [[String: Any]]?, expectedCommand: String) -> Bool {
        entries?.contains { entry in
            (entry["hooks"] as? [[String: Any]])?.contains {
                $0["command"] as? String == expectedCommand
            } == true
        } == true
    }

    private static func mergeHookArray(existing: [[String: Any]]?, kajiHook: [String: Any]) -> [[String: Any]] {
        var entries = existing ?? []
        entries.removeAll { isKajiHookEntry($0) }
        entries.append(kajiHook)
        return entries
    }

    private static func isKajiHookEntry(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return obsoleteMarkers.contains { command.contains($0) }
        }
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath),
              let json = try JSONSerialization.jsonObject(
                  with: Data(contentsOf: URL(fileURLWithPath: settingsPath))
              ) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            atPath: (settingsPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsPath)
    }
}

typealias ClaudeCodeProvider = ClaudeCodeAgentModule

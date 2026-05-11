import Foundation

struct PiAgentModule: CodingAgentModule {
    let socketTypeKey = "pi"
    let mcpServerConfigProvider: MCPServerConfigProvider? = PiMCPServerConfigProvider()

    let definition = CodingAgentDefinition(
        id: "pi",
        displayName: "Pi",
        annotationValues: ["pi", "pi-coding-agent"],
        iconName: "pi",
        executableNames: ["pi"],
        executableSearchDirectories: [],
        defaultCommand: "pi",
        installCommand: .init(executable: "/bin/zsh", arguments: ["-lc", "npm install -g @mariozechner/pi-coding-agent"]),
        configDirectories: [".pi/agent"],
        dataDirectories: [".pi/agent/sessions"],
        hookStrategy: .none,
        historyStrategy: .jsonlFiles(".pi/agent/sessions"),
        modelStrategy: .command(.init(executableName: "pi", arguments: ["--offline", "--list-models"])),
        usageStrategy: .none,
        commandProfile: .init(
            prompt: .positional,
            modelFlag: "--model",
            resume: .flag("--session"),
            skillInvocation: .slashCommand(prefix: "/skill:")
        ),
        models: [],
        defaultModel: nil,
        modelListCommand: .init(executableName: "pi", arguments: ["--offline", "--list-models"]),
        stopEscapeCount: 1,
        globalInstructionFiles: [".pi/agent/AGENTS.md"],
        projectInstructionFiles: ["AGENTS.md", "CLAUDE.md"],
        homeSkillDirectories: [".pi/agent/skills", ".agents/skills"],
        projectSkillDirectories: [".pi/skills", ".agents/skills"]
    )

    func modelOptions(projectPath: String?) -> [String] {
        PiAgentModels.options()
    }

    func historyOptions(
        projectPath: String?,
        query: String,
        limit: Int,
        env: [String: String],
        fileManager: FileManager
    ) -> [AskHistoryOption] {
        PiAgentHistory.options(projectPath: projectPath, query: query, limit: limit, env: env, fileManager: fileManager)
    }

    func install(hookClientPath: String) throws {
        try install(hookClientPath: hookClientPath, homeDirectory: NSHomeDirectory(), fileManager: .default)
    }

    func uninstall() throws {
        for path in Self.extensionPaths() where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    func install(hookClientPath: String, homeDirectory: String, fileManager: FileManager) throws {
        guard let source = Self.findExtensionSource(near: hookClientPath) else { return }
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: source))
        for path in Self.extensionPaths(homeDirectory: homeDirectory) {
            let existingData = try? Data(contentsOf: URL(fileURLWithPath: path))
            guard !fileManager.fileExists(atPath: path) || existingData != sourceData else { continue }
            try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: path) { try fileManager.removeItem(atPath: path) }
            try fileManager.copyItem(atPath: source, toPath: path)
        }
    }

    static func extensionPaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        ["\(homeDirectory)/.pi/agent/extensions/kaji-notify.ts"]
    }

    private static func findExtensionSource(near hookClientPath: String) -> String? {
        if let bundled = KajiNotificationHooks.scriptPath(
            named: "pi-kaji-extension",
            extension: "ts",
            subdirectory: "CodingAgents/Pi"
        ) { return bundled }
        let candidate = ((hookClientPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("pi-kaji-extension.ts")
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }
}

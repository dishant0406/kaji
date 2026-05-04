import Foundation

struct PiAgentModule: CodingAgentModule {
    let socketTypeKey = "pi"

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
}

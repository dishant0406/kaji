import Foundation

struct KajiCodeAgentModule: CodingAgentModule {
    let socketTypeKey = "kajicode"

    let definition = CodingAgentDefinition(
        id: "kajicode",
        displayName: "KajiCode",
        annotationValues: ["kajicode", "kaji-code", "kaji code"],
        iconName: "kaji",
        executableNames: ["kajicode"],
        executableSearchDirectories: [],
        defaultCommand: "kajicode",
        installCommand: nil,
        configDirectories: [".kajicode"],
        dataDirectories: [".local/share/kajicode"],
        hookStrategy: .none,
        historyStrategy: .custom("KajiCode sessions"),
        modelStrategy: .staticList,
        usageStrategy: .none,
        commandProfile: .init(
            prompt: .positional,
            modelFlag: "--model",
            resume: .unsupported,
            skillInvocation: .slashCommand(prefix: "/")
        ),
        models: ["gpt-5.5", "gpt-5.4", "claude-sonnet-4-6", "claude-opus-4-7"],
        defaultModel: nil,
        modelListCommand: nil,
        stopEscapeCount: 1,
        globalInstructionFiles: [".kajicode/AGENTS.md", ".agents/AGENTS.md"],
        projectInstructionFiles: ["AGENTS.md", "AGENTS.override.md"],
        homeSkillDirectories: [".local/share/kajicode/skills", ".agents/skills"],
        projectSkillDirectories: [".agents/skills"],
        processMatchNames: ["kajicode"],
        processCommandMarkers: ["kajicode", ".kajicode", "KajiCode"],
        processKillPatterns: ["kajicode"]
    )
}

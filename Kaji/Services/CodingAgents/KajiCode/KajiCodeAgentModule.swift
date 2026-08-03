import Foundation

struct KajiCodeAgentModule: CodingAgentModule {
    let socketTypeKey = "kajicode"
    let mcpServerConfigProvider: MCPServerConfigProvider? = KajiCodeMCPServerConfigProvider()

    let definition = CodingAgentDefinition(
        id: "kajicode",
        displayName: "KajiCode",
        annotationValues: ["kajicode", "kaji-code", "kaji code"],
        iconName: "kaji",
        executableNames: ["kajicode"],
        defaultCommand: "kajicode",
        installCommand: nil,
        configDirectories: [".kajicode"],
        dataDirectories: [".local/share/kajicode"],
        hookStrategy: .nativeConfig("kajicode hooks"),
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

    func isToolInstalled() -> Bool {
        KajiCodeRuntimeLocator.resolve() != nil
    }

    func resolveExecutable(
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        excluding _: URL?
    ) -> URL? {
        KajiCodeRuntimeLocator.resolve(
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )?.binaryURL
    }

    func install(hookClientPath: String) throws {
        guard let resolution = KajiCodeRuntimeLocator.resolve() else { throw KajiCodeSetupError.binaryMissing }
        _ = try install(binaryURL: resolution.binaryURL, hookClientPath: hookClientPath)
    }

    func uninstall() throws {
        guard let resolution = KajiCodeRuntimeLocator.resolve() else { return }
        try uninstall(binaryURL: resolution.binaryURL)
    }

    func install(
        binaryURL: URL,
        hookClientPath: String,
        environment: [String: String]? = nil
    ) throws -> [KajiCodeHookInstallOutcome] {
        try KajiCodeHookInstallService.install(binaryURL: binaryURL, hookClientPath: hookClientPath, environment: environment)
    }

    func uninstall(binaryURL: URL, environment: [String: String]? = nil) throws {
        _ = try KajiCodeHookInstallService.uninstall(binaryURL: binaryURL, environment: environment)
    }
}

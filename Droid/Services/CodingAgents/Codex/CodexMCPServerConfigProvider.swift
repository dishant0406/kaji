import Foundation

struct CodexMCPServerConfigProvider: MCPServerConfigProvider {
    func mcpServerLocations(projectPath: String?, homeDirectory: String) -> [MCPServerConfigLocation] {
        [
            MCPServerLocationFactory.user(
                agentID: "codex",
                title: "Codex user config.toml",
                homeDirectory: homeDirectory,
                relativePath: ".codex/config.toml",
                format: .codexTOML
            ),
        ] + MCPServerLocationFactory.project(
            agentID: "codex",
            title: "Codex project config.toml",
            projectPath: projectPath,
            relativePath: ".codex/config.toml",
            format: .codexTOML
        )
    }

    func runtimeMCPServers(projectPath: String?, homeDirectory: String) -> [MCPServerRuntimeRecord] {
        guard let output = MCPRuntimeCommandRunner.run(
            executableName: "codex",
            arguments: ["mcp", "list"],
            projectPath: projectPath,
            homeDirectory: homeDirectory
        ) else { return [] }
        return MCPRuntimeListParser.parseCodexList(output)
    }
}

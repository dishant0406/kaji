import Foundation

struct OpenCodeMCPServerConfigProvider: MCPServerConfigProvider {
    func mcpServerLocations(projectPath: String?, homeDirectory: String) -> [MCPServerConfigLocation] {
        [
            MCPServerLocationFactory.user(
                agentID: "opencode",
                title: "OpenCode user opencode.json",
                homeDirectory: homeDirectory,
                relativePath: ".config/opencode/opencode.json",
                format: .openCodeJSON
            ),
            MCPServerLocationFactory.user(
                agentID: "opencode",
                title: "OpenCode legacy opencode.json",
                homeDirectory: homeDirectory,
                relativePath: ".opencode/opencode.json",
                format: .openCodeJSON
            ),
            MCPServerLocationFactory.user(
                agentID: "opencode",
                title: "OpenCode legacy config.json",
                homeDirectory: homeDirectory,
                relativePath: ".opencode/config.json",
                format: .openCodeJSON
            ),
        ] + MCPServerLocationFactory.project(
            agentID: "opencode",
            title: "OpenCode project opencode.json",
            projectPath: projectPath,
            relativePath: "opencode.json",
            format: .openCodeJSON
        )
    }

    func runtimeMCPServers(projectPath: String?, homeDirectory: String) -> [MCPServerRuntimeRecord] {
        guard let output = MCPRuntimeCommandRunner.run(
            executableName: "opencode",
            arguments: ["mcp", "list"],
            projectPath: projectPath,
            homeDirectory: homeDirectory
        ) else { return [] }
        return MCPRuntimeListParser.parseOpenCodeList(output)
    }
}

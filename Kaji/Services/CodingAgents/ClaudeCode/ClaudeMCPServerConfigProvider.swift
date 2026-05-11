import Foundation

struct ClaudeMCPServerConfigProvider: MCPServerConfigProvider {
    func mcpServerLocations(projectPath: String?, homeDirectory: String) -> [MCPServerConfigLocation] {
        [
            MCPServerLocationFactory.user(
                agentID: "claude",
                title: "Claude user .claude.json",
                homeDirectory: homeDirectory,
                relativePath: ".claude.json",
                format: .standardJSON
            ),
        ] + MCPServerLocationFactory.project(
            agentID: "claude",
            title: "Claude project .mcp.json",
            projectPath: projectPath,
            relativePath: ".mcp.json",
            format: .standardJSON
        )
    }

    func readMCPServers(location: MCPServerConfigLocation) throws -> [MCPServer] {
        guard FileManager.default.fileExists(atPath: location.url.path) else { return [] }
        let data = try Data(contentsOf: location.url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPServerConfigError.invalidRoot
        }
        if let mcpServers = root["mcpServers"] as? [String: Any] {
            return MCPJSONConfigCodec.standardServers(from: mcpServers)
        }
        guard location.scope == .user else { return [] }
        let userServers = MCPJSONConfigCodec.standardServers(from: root["mcpServers"] as? [String: Any] ?? [:])
        let projectServers = projectServers(from: root["projects"] as? [String: Any])
        return userServers + projectServers
    }

    func runtimeMCPServers(projectPath: String?, homeDirectory: String) -> [MCPServerRuntimeRecord] {
        guard let output = MCPRuntimeCommandRunner.run(
            executableName: "claude",
            arguments: ["mcp", "list"],
            projectPath: projectPath,
            homeDirectory: homeDirectory
        )
        else { return [] }
        return MCPRuntimeListParser.parseClaudeList(output)
    }

    private func projectServers(from projects: [String: Any]?) -> [MCPServer] {
        guard let projects else { return [] }
        var result = [MCPServer]()
        for path in projects.keys.sorted() {
            guard let project = projects[path] as? [String: Any], let servers = project["mcpServers"] as? [String: Any] else { continue }
            result.append(contentsOf: MCPJSONConfigCodec.standardServers(from: servers))
        }
        return result
    }
}

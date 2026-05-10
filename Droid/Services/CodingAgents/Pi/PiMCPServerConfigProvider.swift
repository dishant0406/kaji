import Foundation

struct PiMCPServerConfigProvider: MCPServerConfigProvider {
    func mcpServerLocations(projectPath: String?, homeDirectory: String) -> [MCPServerConfigLocation] {
        [
            MCPServerLocationFactory.user(
                agentID: "pi",
                title: "Pi user mcp.json",
                homeDirectory: homeDirectory,
                relativePath: ".pi/agent/mcp.json",
                format: .standardJSON
            ),
            MCPServerLocationFactory.user(
                agentID: "pi",
                title: "Pi MCP cache",
                homeDirectory: homeDirectory,
                relativePath: ".pi/agent/mcp-cache.json",
                format: .standardJSON
            ),
        ] + MCPServerLocationFactory.project(
            agentID: "pi",
            title: "Pi project .mcp.json",
            projectPath: projectPath,
            relativePath: ".mcp.json",
            format: .standardJSON
        )
    }

    func readMCPServers(location: MCPServerConfigLocation) throws -> [MCPServer] {
        guard FileManager.default.fileExists(atPath: location.url.path) else { return [] }
        guard location.url.lastPathComponent == "mcp-cache.json" else {
            return try MCPServerConfigProviderDefault.read(location: location)
        }
        let data = try Data(contentsOf: location.url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["servers"] as? [String: Any]
        else { return [] }
        return servers.keys.sorted().map { name in
            var server = MCPServer.empty()
            server.name = name
            server.transport = .plugin
            server.pluginID = name
            return MCPServerRuntimeMetadataReader.enriched(server, location: location)
        }
    }
}

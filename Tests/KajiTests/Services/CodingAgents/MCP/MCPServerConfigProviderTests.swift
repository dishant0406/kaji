import Foundation
import Testing

@testable import Kaji

struct MCPServerConfigProviderTests {
    @Test
    func everySupportedAgentOwnsItsMCPProvider() throws {
        let expected = ["claude", "codex", "opencode", "pi"]

        for id in expected {
            let agent = try #require(CodingAgentRegistry.shared.agent(id: id))
            #expect(agent.mcpServerConfigProvider != nil)
        }
    }

    @Test
    func codexProviderReportsUserAndProjectConfigLocations() throws {
        let agent = try #require(CodingAgentRegistry.shared.agent(id: "codex"))
        let provider = try #require(agent.mcpServerConfigProvider)

        let locations = provider.mcpServerLocations(projectPath: "/tmp/project", homeDirectory: "/Users/test")

        #expect(locations.map(\.title) == ["Codex user config.toml", "Codex project config.toml"])
        #expect(locations.map(\.url.path) == ["/Users/test/.codex/config.toml", "/tmp/project/.codex/config.toml"])
    }

    @Test
    func claudeProviderReadsProjectServersFromClaudeState() throws {
        let provider = ClaudeMCPServerConfigProvider()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(".claude.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "projects": {
            "/tmp/project": {
              "mcpServers": {
                "kaji-browser": { "type": "stdio", "command": "kaji-browser-mcp", "args": [] }
              }
            }
          }
        }
        """.data(using: .utf8)?.write(to: url)
        let location = MCPServerConfigLocation(id: "claude:test", agentID: "claude", title: "Claude state", scope: .user, url: url, format: .standardJSON)

        let servers = try provider.readMCPServers(location: location)

        #expect(servers.map(\.name) == ["kaji-browser"])
        #expect(servers[0].command == "kaji-browser-mcp")
    }

    @Test
    func piProviderReadsCachedMCPServers() throws {
        let provider = PiMCPServerConfigProvider()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mcp-cache.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        { "version": 1, "servers": { "next-devtools": { "tools": [] } } }
        """.data(using: .utf8)?.write(to: url)
        let location = MCPServerConfigLocation(id: "pi:test", agentID: "pi", title: "Pi cache", scope: .user, url: url, format: .standardJSON)

        let servers = try provider.readMCPServers(location: location)

        #expect(servers.map(\.name) == ["next-devtools"])
        #expect(servers[0].transport == .plugin)
    }

    @Test
    func piProviderReadsCachedToolNames() throws {
        let provider = PiMCPServerConfigProvider()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mcp-cache.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "version": 1,
          "servers": {
            "next-devtools": {
              "cachedAt": 1778417851895,
              "tools": [
                { "name": "nextjs_index" },
                { "name": "nextjs_call" }
              ]
            }
          }
        }
        """.data(using: .utf8)?.write(to: url)
        let location = MCPServerConfigLocation(id: "pi:test", agentID: "pi", title: "Pi cache", scope: .user, url: url, format: .standardJSON)

        let servers = try provider.readMCPServers(location: location)

        #expect(servers[0].toolNames == ["nextjs_call", "nextjs_index"])
        #expect(servers[0].runtimeSummary?.contains("2 runtime tools") == true)
    }
}

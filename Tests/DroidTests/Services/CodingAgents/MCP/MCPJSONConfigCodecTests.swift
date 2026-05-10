import Foundation
import Testing

@testable import Droid

struct MCPJSONConfigCodecTests {
    @Test
    func readsStandardJSONServers() throws {
        let data = try #require("""
        {
          "mcpServers": {
            "filesystem": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-filesystem"],
              "env": { "ROOT": "/tmp" },
              "directTools": true
            }
          }
        }
        """.data(using: .utf8))

        let servers = try MCPJSONConfigCodec.read(data: data, format: .standardJSON)

        #expect(servers.count == 1)
        #expect(servers[0].name == "filesystem")
        #expect(servers[0].command == "npx")
        #expect(servers[0].arguments == ["-y", "@modelcontextprotocol/server-filesystem"])
        #expect(servers[0].environment["ROOT"] == "/tmp")
        #expect(servers[0].directTools)
    }

    @Test
    func writesOpenCodeServerWithoutRemovingPluginConfig() throws {
        let existing = try #require("""
        {
          "$schema": "https://opencode.ai/config.json",
          "plugin": ["file:///tmp/droid-notify.js"]
        }
        """.data(using: .utf8))
        var server = MCPServer.empty()
        server.name = "browser"
        server.command = "node"
        server.arguments = ["server.js"]
        server.environment = ["TOKEN": "abc"]

        let data = try MCPJSONConfigCodec.write(servers: [server], existingData: existing, format: .openCodeJSON)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plugins = try #require(root["plugin"] as? [String])
        let mcp = try #require(root["mcp"] as? [String: Any])
        let browser = try #require(mcp["browser"] as? [String: Any])

        #expect(plugins == ["file:///tmp/droid-notify.js"])
        #expect(browser["type"] as? String == "local")
        #expect(browser["command"] as? [String] == ["node", "server.js"])
    }
}

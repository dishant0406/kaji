import Foundation
import Testing

@testable import Droid

struct MCPCodexTOMLCodecTests {
    @Test
    func readsCodexMCPServers() {
        let content = """
        model = "gpt-5.5"

        [mcp_servers.filesystem]
        command = "npx"
        args = ["-y", "@modelcontextprotocol/server-filesystem"]
        env = { ROOT = "/tmp" }

        [mcp_servers.remote]
        url = "https://example.com/mcp"
        bearer_token_env_var = "API_TOKEN"
        """

        let servers = MCPCodexTOMLCodec.read(content)

        #expect(servers.count == 2)
        #expect(servers[0].name == "filesystem")
        #expect(servers[0].command == "npx")
        #expect(servers[0].arguments == ["-y", "@modelcontextprotocol/server-filesystem"])
        #expect(servers[0].environment["ROOT"] == "/tmp")
        #expect(servers[1].transport == .remote)
        #expect(servers[1].bearerTokenEnvVar == "API_TOKEN")
    }

    @Test
    func readsCodexMarketplacePluginsAsMCPEntries() {
        let content = """
        [plugins."github@openai-curated"]
        enabled = true

        [plugins."computer-use@openai-bundled"]
        enabled = true
        """

        let servers = MCPCodexTOMLCodec.read(content)

        #expect(servers.map(\.name) == ["computer-use", "github"])
        #expect(servers.allSatisfy { $0.transport == .plugin })
        #expect(servers.first { $0.name == "github" }?.pluginID == "github@openai-curated")
    }

    @Test
    func writesCodexMCPServersPreservingNonMCPSettings() {
        let existing = """
        model = "gpt-5.5"

        [mcp_servers.old]
        command = "node"
        args = []

        [profiles.work]
        model = "gpt-5.4"
        """
        var server = MCPServer.empty()
        server.name = "filesystem"
        server.command = "npx"
        server.arguments = ["-y", "pkg"]
        server.environment = ["ROOT": "/tmp"]

        let output = MCPCodexTOMLCodec.write(servers: [server], existingContent: existing)

        #expect(output.contains("model = \"gpt-5.5\""))
        #expect(output.contains("[profiles.work]"))
        #expect(!output.contains("[mcp_servers.old]"))
        #expect(output.contains("[mcp_servers.filesystem]"))
        #expect(output.contains("env = { ROOT = \"/tmp\" }"))
    }

    @Test
    func writingCodexServersDoesNotPersistPluginEntriesAsMCPServers() {
        let existing = """
        [plugins."github@openai-curated"]
        enabled = true
        """
        let plugin = MCPCodexTOMLCodec.read(existing)[0]

        let output = MCPCodexTOMLCodec.write(servers: [plugin], existingContent: existing)

        #expect(output.contains("[plugins.\"github@openai-curated\"]"))
        #expect(!output.contains("[mcp_servers.github]"))
    }
}

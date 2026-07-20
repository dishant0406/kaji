import Foundation
import Testing

@testable import Kaji

struct KajiCodeMCPServerConfigProviderTests {
    @Test
    func readsAndWritesKajiCodeNestedMCPServers() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        let provider = KajiCodeMCPServerConfigProvider()
        let location = try #require(provider.mcpServerLocations(projectPath: nil, homeDirectory: home.path).first)
        let existing = #"{"activeProvider":"openai","mcp":{"servers":{"old":{"type":"stdio","command":"old","disabled":true}}}}"#
        try fileManager.createDirectory(at: location.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(existing.utf8).write(to: location.url)

        let initial = try provider.readMCPServers(location: location)
        var next = MCPServer.empty()
        next.name = "filesystem"
        next.command = "/usr/bin/env"
        next.arguments = ["node", "server.js"]
        next.type = "stdio"
        try provider.writeMCPServers([next], location: location)
        let reloaded = try provider.readMCPServers(location: location)

        #expect(initial.first?.name == "old")
        #expect(initial.first?.enabled == false)
        #expect(reloaded == [next])
        let data = try Data(contentsOf: location.url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["activeProvider"] as? String == "openai")
        let mcp = try #require(root["mcp"] as? [String: Any])
        let servers = try #require(mcp["servers"] as? [String: Any])
        let filesystem = try #require(servers["filesystem"] as? [String: Any])
        #expect(filesystem["command"] as? String == "/usr/bin/env")
        #expect(filesystem["args"] as? [String] == ["node", "server.js"])
    }
}

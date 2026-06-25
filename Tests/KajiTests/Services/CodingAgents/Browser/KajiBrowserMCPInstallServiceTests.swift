import Foundation
import Testing

@testable import Kaji

@MainActor
struct KajiBrowserMCPInstallServiceTests {
    @Test
    func installsBrowserMCPIntoUserAgentConfigsWithoutSessionEnvironment() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)

        let outcomes = KajiBrowserMCPInstallService.installAll(homeDirectory: home.path)

        #expect(outcomes.allSatisfy { $0.installed })
        #expect(KajiBrowserMCPBinaryInstaller.isInstalled(homeDirectory: home.path))
        #expect(Set(KajiBrowserMCPInstallService.installedAgentIDs(homeDirectory: home.path)) == Set(["codex", "claude", "opencode", "pi"]))
        try assertCodexConfig(home: home)
        try assertStandardConfig(home: home.appendingPathComponent(".claude.json"))
        try assertOpenCodeConfig(home: home.appendingPathComponent(".config/opencode/opencode.json"))
        try assertStandardConfig(home: home.appendingPathComponent(".pi/agent/mcp.json"))
    }

    @Test
    func uninstallRemovesConfigsAndCommand() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        _ = KajiBrowserMCPInstallService.installAll(homeDirectory: home.path)

        let outcomes = KajiBrowserMCPInstallService.uninstallAll(homeDirectory: home.path)

        #expect(outcomes.allSatisfy { !$0.installed })
        #expect(!KajiBrowserMCPBinaryInstaller.isInstalled(homeDirectory: home.path))
        #expect(KajiBrowserMCPInstallService.installedAgentIDs(homeDirectory: home.path).isEmpty)
        let codex = try config(home.appendingPathComponent(".codex/config.toml"))
        let claude = try config(home.appendingPathComponent(".claude.json"))
        let opencode = try config(home.appendingPathComponent(".config/opencode/opencode.json"))
        let pi = try config(home.appendingPathComponent(".pi/agent/mcp.json"))
        #expect(!codex.contains("[mcp_servers.kaji-browser]"))
        #expect(!claude.contains("kaji-browser"))
        #expect(!opencode.contains("kaji-browser"))
        #expect(!pi.contains("kaji-browser"))
    }

    @Test
    func missingCommandIsReportedAsNotInstalled() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        _ = KajiBrowserMCPInstallService.installAll(homeDirectory: home.path)
        try KajiBrowserMCPBinaryInstaller.remove(homeDirectory: home.path)

        #expect(KajiBrowserMCPInstallService.installedAgentIDs(homeDirectory: home.path).isEmpty)
    }

    private func assertCodexConfig(home: URL) throws {
        let content = try config(home.appendingPathComponent(".codex/config.toml"))
        #expect(content.contains("[mcp_servers.kaji-browser]"))
        #expect(content.contains("command = \""))
        #expect(!content.contains("KAJI_BROWSER_MCP_TOKEN"))
    }

    private func assertStandardConfig(home: URL) throws {
        let data = try Data(contentsOf: home)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(root["mcpServers"] as? [String: Any])
        let server = try #require(servers["kaji-browser"] as? [String: Any])
        #expect(server["command"] as? String != nil)
        #expect(server["env"] == nil)
    }

    private func assertOpenCodeConfig(home: URL) throws {
        let data = try Data(contentsOf: home)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(root["mcp"] as? [String: Any])
        let server = try #require(servers["kaji-browser"] as? [String: Any])
        #expect(server["type"] as? String == "local")
        #expect(server["environment"] == nil)
    }

    private func config(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

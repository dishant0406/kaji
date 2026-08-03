import Foundation
import Testing

@testable import Kaji

@MainActor
struct KajiCodeMCPInstallServiceTests {
    @Test
    func installsKajiCodeMCPIntoSupportedUserAgentConfigs() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        let binary = try executable(in: home)

        let outcomes = KajiCodeMCPInstallService.installAll(binaryURL: binary, homeDirectory: home.path)

        #expect(outcomes.allSatisfy { $0.installed })
        #expect(Set(KajiCodeMCPInstallService.installedAgentIDs(homeDirectory: home.path)) == Set(["codex", "claude", "opencode", "pi"]))
        try assertCodexConfig(home: home, binary: binary)
        try assertStandardConfig(home.appendingPathComponent(".claude.json"), binary: binary)
        try assertOpenCodeConfig(home.appendingPathComponent(".config/opencode/opencode.json"), binary: binary)
        try assertStandardConfig(home.appendingPathComponent(".pi/agent/mcp.json"), binary: binary)
    }

    @Test
    func installsShellPathEnvironmentForKajiCodeMCP() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        let binary = try executable(in: home)

        _ = KajiCodeMCPInstallService.installAll(
            binaryURL: binary,
            homeDirectory: home.path,
            environment: ["PATH": "/shell/bin:/usr/bin"]
        )

        try assertStandardEnvironment(home.appendingPathComponent(".claude.json"), path: "/shell/bin:/usr/bin")
        let content = try config(home.appendingPathComponent(".codex/config.toml"))
        #expect(content.contains("PATH = \"/shell/bin:/usr/bin\""))
    }

    @Test
    func uninstallRemovesKajiCodeMCPEntries() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        let binary = try executable(in: home)
        _ = KajiCodeMCPInstallService.installAll(binaryURL: binary, homeDirectory: home.path)

        let outcomes = KajiCodeMCPInstallService.uninstallAll(homeDirectory: home.path)

        #expect(outcomes.allSatisfy { !$0.installed })
        #expect(KajiCodeMCPInstallService.installedAgentIDs(homeDirectory: home.path).isEmpty)
        let codex = try config(home.appendingPathComponent(".codex/config.toml"))
        let claude = try config(home.appendingPathComponent(".claude.json"))
        let opencode = try config(home.appendingPathComponent(".config/opencode/opencode.json"))
        let pi = try config(home.appendingPathComponent(".pi/agent/mcp.json"))
        #expect(!codex.contains("[mcp_servers.kajicode]"))
        #expect(!claude.contains("kajicode"))
        #expect(!opencode.contains("kajicode"))
        #expect(!pi.contains("kajicode"))
    }

    private func assertCodexConfig(home: URL, binary: URL) throws {
        let content = try config(home.appendingPathComponent(".codex/config.toml"))
        #expect(content.contains("[mcp_servers.kajicode]"))
        #expect(content.contains("command = \"\(binary.path)\""))
        #expect(content.contains("\"serve\""))
        #expect(content.contains("\"--mcp\""))
    }

    private func assertStandardConfig(_ url: URL, binary: URL) throws {
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(root["mcpServers"] as? [String: Any])
        let server = try #require(servers["kajicode"] as? [String: Any])
        #expect(server["command"] as? String == binary.path)
        #expect(server["args"] as? [String] == ["serve", "--mcp"])
    }

    private func assertStandardEnvironment(_ url: URL, path: String) throws {
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(root["mcpServers"] as? [String: Any])
        let server = try #require(servers["kajicode"] as? [String: Any])
        let env = try #require(server["env"] as? [String: String])
        #expect(env == ["PATH": path])
    }

    private func assertOpenCodeConfig(_ url: URL, binary: URL) throws {
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(root["mcp"] as? [String: Any])
        let server = try #require(servers["kajicode"] as? [String: Any])
        #expect(server["command"] as? [String] == [binary.path, "serve", "--mcp"])
    }

    private func executable(in home: URL) throws -> URL {
        let url = home.appendingPathComponent("kajicode")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func config(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

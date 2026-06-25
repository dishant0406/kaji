import Foundation
import Testing

@testable import Kaji

@MainActor
struct CodingAgentShimInstallerTests {
    @Test
    func installsExecutableShimsWithoutBrowserMCPByDefault() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }

        let directory = try #require(CodingAgentShimInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager
        ))

        for name in ["codex", "claude", "claude-code", "opencode", "pi"] {
            let path = directory.appendingPathComponent(name).path
            #expect(fileManager.isExecutableFile(atPath: path))
            let text = try String(contentsOfFile: path, encoding: .utf8)
            #expect(text.contains("exec \"$real\""))
            #expect(text.contains("\"$@\""))
        }
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("kaji-browser-mcp").path))
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("kaji-browser/main.js").path))
    }

    @Test
    func regularShimInstallDoesNotRemoveManualBrowserMCP() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }

        let command = try KajiBrowserMCPBinaryInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager
        )
        #expect(fileManager.isExecutableFile(atPath: command.path))

        let directory = try #require(CodingAgentShimInstaller.install(
            homeDirectory: home.path,
            fileManager: fileManager
        ))
        #expect(fileManager.isExecutableFile(atPath: directory.appendingPathComponent("kaji-browser-mcp").path))
        #expect(fileManager.fileExists(atPath: directory.appendingPathComponent("kaji-browser/main.js").path))
    }
}

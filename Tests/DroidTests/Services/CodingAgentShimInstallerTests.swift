import Foundation
import Testing

@testable import Droid

@MainActor
struct CodingAgentShimInstallerTests {
    @Test
    func installsExecutableShims() throws {
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
            #expect(!text.contains(["DROID", "BROWSER"].joined(separator: "_")))
        }
    }

}

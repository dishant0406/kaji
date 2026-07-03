import Foundation
import Testing

@testable import Kaji

struct KajiCodeGraphMCPInstallServiceTests {
    @Test
    func installsAndUninstallsUserMCPConfigEntries() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: home) }
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)

        let outcomes = KajiCodeGraphMCPInstallService.installAll(homeDirectory: home.path)
        let installed = KajiCodeGraphMCPInstallService.installedAgentIDs(homeDirectory: home.path)

        #expect(outcomes.contains { $0.agentID == "codex" && $0.installed })
        #expect(installed.contains("codex"))
        #expect(fileManager.isExecutableFile(atPath: home.appendingPathComponent(".kaji/bin/kaji-codegraph-mcp").path))

        let uninstallOutcomes = KajiCodeGraphMCPInstallService.uninstallAll(homeDirectory: home.path)
        let after = KajiCodeGraphMCPInstallService.installedAgentIDs(homeDirectory: home.path)

        #expect(uninstallOutcomes.contains { $0.agentID == "codex" && !$0.installed })
        #expect(after.isEmpty)
    }
}

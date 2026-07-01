import Foundation
import Testing

@testable import Kaji

struct AgentInstructionDiscoveryGitIgnoreTests {
    @Test
    func respectsRepositoryGitignoreWhenDiscoveringNestedInstructions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try runGit(["init"], in: project)
        try write("generated/\n", to: project.appendingPathComponent(".gitignore"))
        try write("project", to: project.appendingPathComponent("AGENTS.md"))
        try write("ignored", to: project.appendingPathComponent("generated/AGENTS.md"))

        let codex = try #require(CodingAgentRegistry.shared.definition(id: "codex"))
        let groups = AgentInstructionDiscovery.discover(
            projectPath: project.path,
            definitions: [codex],
            homeDirectory: home.path,
            fileManager: .default
        )

        let documents = try #require(groups.first?.documents)
        #expect(documents.map(\.displayPath) == ["AGENTS.md"])
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

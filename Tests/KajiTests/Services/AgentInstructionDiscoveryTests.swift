import Foundation
import Testing

@testable import Kaji

@Suite("AgentInstructionDiscovery")
struct AgentInstructionDiscoveryTests {
    @Test("discovers global project and nested instruction files")
    func discoversInstructionHierarchy() throws {
        let root = temporaryDirectory()
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        try write("global", to: home.appendingPathComponent(".codex/AGENTS.md"))
        try write("project", to: project.appendingPathComponent("AGENTS.md"))
        try write("nested", to: project.appendingPathComponent("Sources/AGENTS.override.md"))
        try write("ignored", to: project.appendingPathComponent("Vendor/AGENTS.md"))

        let codex = try #require(CodingAgentRegistry.shared.definition(id: "codex"))
        let groups = AgentInstructionDiscovery.discover(
            projectPath: project.path,
            definitions: [codex],
            homeDirectory: home.path,
            fileManager: .default
        )

        let documents = try #require(groups.first?.documents)
        #expect(documents.map(\.scope) == [.global, .project, .nested])
        #expect(documents.map(\.displayPath) == ["~/.codex/AGENTS.md", "AGENTS.md", "Sources/AGENTS.override.md"])
        #expect(documents.map(\.content) == ["global", "project", "nested"])
    }

    @Test("Claude includes local project instructions")
    func claudeIncludesLocalInstructions() throws {
        let root = temporaryDirectory()
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        try write("personal", to: project.appendingPathComponent("CLAUDE.local.md"))

        let claude = try #require(CodingAgentRegistry.shared.definition(id: "claude"))
        let groups = AgentInstructionDiscovery.discover(
            projectPath: project.path,
            definitions: [claude],
            homeDirectory: home.path,
            fileManager: .default
        )

        #expect(groups.first?.documents.first?.displayPath == "CLAUDE.local.md")
        #expect(groups.first?.documents.first?.content == "personal")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

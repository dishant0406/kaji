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

    @Test("skips generated and symlinked directories")
    func skipsGeneratedAndSymlinkedDirectories() throws {
        let root = temporaryDirectory()
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        let external = root.appendingPathComponent("external")
        try write("project", to: project.appendingPathComponent("AGENTS.md"))
        try write("ignored", to: project.appendingPathComponent("dist/AGENTS.md"))
        try write("linked", to: external.appendingPathComponent("AGENTS.md"))
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("Linked"),
            withDestinationURL: external
        )

        let codex = try #require(CodingAgentRegistry.shared.definition(id: "codex"))
        let groups = AgentInstructionDiscovery.discover(
            projectPath: project.path,
            definitions: [codex],
            homeDirectory: home.path,
            fileManager: .default
        )

        let documents = try #require(groups.first?.documents)
        #expect(documents.map(\.displayPath) == ["AGENTS.md"])
        #expect(documents.map(\.content) == ["project"])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
@Suite("AgentInstructionPanelState")
struct AgentInstructionPanelStateTests {
    @Test("refresh is asynchronous and preserves selection")
    func refreshLoadsOffMainAndPreservesSelection() async throws {
        let state = AgentInstructionPanelState { _, descriptors, _ in
            try? await Task.sleep(for: .milliseconds(30))
            return descriptors.map { descriptor in
                AgentInstructionGroup(
                    id: descriptor.id,
                    displayName: descriptor.displayName,
                    iconName: descriptor.iconName,
                    documents: [
                        Self.document(agentID: descriptor.id, path: "/repo/AGENTS.md"),
                        Self.document(agentID: descriptor.id, path: "/repo/Sources/AGENTS.override.md"),
                    ]
                )
            }
        }

        state.refreshIfNeeded(projectPath: "/repo", enabledLaunchers: [launcher(id: "codex")])
        #expect(state.isLoading)
        #expect(state.groups.isEmpty)

        try await waitUntil { !state.isLoading }
        state.selectDocument("codex:/repo/Sources/AGENTS.override.md")
        state.refresh(projectPath: "/repo", enabledLaunchers: [launcher(id: "codex")])
        try await waitUntil { !state.isLoading }

        #expect(state.groups.first?.documents.count == 2)
        #expect(state.selectedDocument?.path == "/repo/Sources/AGENTS.override.md")
    }

    @Test("cancelled refresh does not apply stale results")
    func cancelledRefreshDoesNotApplyStaleResults() async throws {
        let state = AgentInstructionPanelState { _, descriptors, _ in
            try? await Task.sleep(for: .milliseconds(40))
            return descriptors.map { descriptor in
                AgentInstructionGroup(
                    id: descriptor.id,
                    displayName: descriptor.displayName,
                    iconName: descriptor.iconName,
                    documents: [Self.document(agentID: descriptor.id, path: "/repo/AGENTS.md")]
                )
            }
        }

        state.refreshIfNeeded(projectPath: "/repo", enabledLaunchers: [launcher(id: "codex")])
        state.cancelRefresh()
        try await Task.sleep(for: .milliseconds(70))

        #expect(!state.isLoading)
        #expect(state.groups.isEmpty)
    }

    @Test("failed refresh exposes retryable error")
    func failedRefreshExposesRetryableError() async throws {
        let state = AgentInstructionPanelState { _, _, _ in
            throw AgentInstructionPanelStateTestError.failed
        }

        state.refreshIfNeeded(projectPath: "/repo", enabledLaunchers: [launcher(id: "codex")])
        try await waitUntil { !state.isLoading }

        #expect(state.groups.isEmpty)
        #expect(state.errorMessage == "failed")
    }

    private func launcher(id: String) -> CLILauncherConfiguration {
        let definition = CLILauncherDefinition(
            id: id,
            displayName: id,
            iconName: "terminal",
            defaultCommand: id
        )
        return CLILauncherConfiguration(id: id, definition: definition, isEnabled: true, command: id)
    }

    nonisolated private static func document(agentID: String, path: String) -> AgentInstructionDocument {
        AgentInstructionDocument(
            id: "\(agentID):\(path)",
            agentID: agentID,
            scope: path.contains("Sources") ? .nested : .project,
            title: URL(fileURLWithPath: path).lastPathComponent,
            displayPath: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            content: path
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private enum AgentInstructionPanelStateTestError: LocalizedError {
    case failed

    var errorDescription: String? { "failed" }
}

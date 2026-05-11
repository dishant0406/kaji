import Foundation
import Testing

@testable import Kaji

struct AgentVerificationRunnerTests {
    @Test
    func swiftPackageRunUsesBuildAndTestCommand() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("Package.swift").path,
            contents: Data()
        )

        var run = AgentRun(
            id: UUID(),
            providerID: "codex",
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            worktreePath: directory.path,
            title: "Codex",
            status: .completed,
            sourceConfidence: .exactPane,
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted,
            startedAt: Date(),
            lastEventAt: Date(),
            events: [],
            actions: []
        )

        let plan = AgentVerificationRunner.plan(for: run)

        #expect(plan?.command == "swift build && swift test")
        #expect(plan?.workingDirectory == directory.path)

        run.worktreePath = nil
        #expect(AgentVerificationRunner.plan(for: run) == nil)
    }

    @Test
    func projectVerificationCommandOverridesAutoDetection() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var project = Project(name: "muxy", path: directory.path)
        project.verificationCommand = "npm test"
        let run = AgentRun(
            id: UUID(),
            providerID: "opencode",
            paneID: UUID(),
            projectID: project.id,
            worktreeID: UUID(),
            worktreePath: directory.path,
            title: "OpenCode",
            status: .completed,
            sourceConfidence: .exactPane,
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted,
            startedAt: Date(),
            lastEventAt: Date(),
            events: [],
            actions: []
        )

        let plan = AgentVerificationRunner.plan(for: run, project: project)

        #expect(plan == .init(command: "npm test", workingDirectory: directory.path))
    }
}

import Foundation
import Testing

@testable import Droid

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
            events: []
        )

        let plan = AgentVerificationRunner.plan(for: run)

        #expect(plan?.command == "swift build && swift test")
        #expect(plan?.workingDirectory == directory.path)

        run.worktreePath = nil
        #expect(AgentVerificationRunner.plan(for: run) == nil)
    }
}

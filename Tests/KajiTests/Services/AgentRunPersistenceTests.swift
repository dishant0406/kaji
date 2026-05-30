import Foundation
import Testing

@testable import Kaji

struct AgentRunPersistenceTests {
    @Test
    func writesSmallIndexAndChunkedChangedFiles() async throws {
        let directory = tempDirectory()
        let persistence = AgentRunPersistence(
            rootURL: directory.appendingPathComponent("AgentRuns", isDirectory: true),
            legacyURL: directory.appendingPathComponent("agent-runs.json")
        )
        let run = makeRun(files: (0 ..< 120).map { changedFile("Sources/File\($0).swift") })

        await persistence.saveImmediately([run])

        let indexURL = directory.appendingPathComponent("AgentRuns/index.json")
        let chunkURL = directory
            .appendingPathComponent("AgentRuns/ChangedFiles/\(run.id.uuidString)/chunk-000.json")
        let indexData = try Data(contentsOf: indexURL)
        let chunkData = try Data(contentsOf: chunkURL)
        let reloaded = persistence.loadRuns()

        #expect(indexData.count < chunkData.count)
        #expect(reloaded.first?.changedFiles.count == 120)
    }

    @Test
    func legacyLoadFiltersOversizedGeneratedFolders() throws {
        let directory = tempDirectory()
        let legacyURL = directory.appendingPathComponent("agent-runs.json")
        let persistence = AgentRunPersistence(
            rootURL: directory.appendingPathComponent("AgentRuns", isDirectory: true),
            legacyURL: legacyURL
        )
        let run = makeRun(files: [
            changedFile("Kaji/App.swift"),
            changedFile("KajiAgentRuntime/node_modules/pkg/index.js")
        ])
        try JSONEncoder().encode([run]).write(to: legacyURL)

        let loaded = persistence.loadRuns()

        #expect(loaded.first?.changedFiles.map(\.path) == ["Kaji/App.swift"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
            $0.hasPrefix("agent-runs.legacy-")
        })
    }

    private func tempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeRun(files: [AgentChangedFile]) -> AgentRun {
        AgentRun(
            id: UUID(),
            providerID: "opencode",
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            worktreePath: "/tmp/project",
            sessionID: "session",
            transcriptPath: nil,
            sessionUpdatedAt: nil,
            title: "OpenCode",
            status: .completed,
            sourceConfidence: .exactPane,
            changedFiles: files,
            changedFilesAttribution: .worktreeSnapshot,
            verification: .notStarted,
            startedAt: Date(),
            lastEventAt: Date(),
            events: [],
            actions: []
        )
    }

    private func changedFile(_ path: String) -> AgentChangedFile {
        AgentChangedFile(
            path: path,
            oldPath: nil,
            status: .modified,
            additions: 1,
            deletions: 0,
            isBinary: false
        )
    }
}

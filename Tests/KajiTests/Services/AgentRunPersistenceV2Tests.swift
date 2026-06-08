import Foundation
import Testing

@testable import Kaji

struct AgentRunPersistenceV2Tests {
    @Test
    func writesSummaryIndexAndDetailSidecars() throws {
        let directory = tempDirectory()
        let rootURL = directory.appendingPathComponent("AgentRuns", isDirectory: true)
        let run = heavyRun()

        try AgentRunPersistenceDiskWriter(rootURL: rootURL, chunkSize: 200).write([run])

        let indexURL = rootURL.appendingPathComponent("index.json")
        let detailURL = rootURL.appendingPathComponent("Details/\(run.id.uuidString).json")
        let indexData = try Data(contentsOf: indexURL)
        let indexText = String(data: indexData, encoding: .utf8) ?? ""
        let snapshot = try JSONDecoder().decode(AgentRunIndexSnapshotV2.self, from: indexData)
        let detail = try JSONDecoder().decode(AgentRunDetailSnapshot.self, from: Data(contentsOf: detailURL))
        let loaded = AgentRunPersistence(rootURL: rootURL, legacyURL: directory.appendingPathComponent("agent-runs.json")).loadRuns()

        #expect(snapshot.version == 2)
        #expect(snapshot.runs.first?.eventCount == 40)
        #expect(snapshot.runs.first?.actionCount == 40)
        #expect(snapshot.runs.first?.changedFilesManifest.storedCount == 500)
        #expect(indexData.count < 80_000)
        #expect(!indexText.contains("event-payload"))
        #expect(!indexText.contains("verification-payload"))
        #expect(detail.events.first?.text.count == 500)
        #expect(detail.actions.first?.message.count == 300)
        #expect(detail.verification.output?.count == 4_000)
        #expect(detail.changedFilesPreview.count == 5)
        #expect(loaded.first?.changedFiles.count == 500)
        #expect(loaded.first?.events.count == 40)
        #expect(loaded.first?.verification.output?.count == 4_000)
    }

    @Test
    func loadsV1IndexAndRewritesV2() throws {
        let directory = tempDirectory()
        let rootURL = directory.appendingPathComponent("AgentRuns", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let run = makeRun(files: [])
        let manifest = AgentRunChangedFilesManifest(totalCount: 0, storedCount: 0, chunkSize: 200, chunkCount: 0)
        let v1 = AgentRunIndexSnapshot(version: 1, runs: [AgentRunIndexRecord(run: run, changedFilesManifest: manifest)])
        try JSONEncoder().encode(v1).write(to: rootURL.appendingPathComponent("index.json"))

        let loaded = AgentRunPersistence(rootURL: rootURL, legacyURL: directory.appendingPathComponent("agent-runs.json")).loadRuns()
        let rewritten = try JSONDecoder().decode(AgentRunIndexSnapshotV2.self, from: Data(contentsOf: rootURL.appendingPathComponent("index.json")))

        #expect(loaded.first?.id == run.id)
        #expect(rewritten.version == 2)
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Details/\(run.id.uuidString).json").path))
    }

    @Test
    func unchangedSidecarsKeepModificationDates() throws {
        let directory = tempDirectory()
        let rootURL = directory.appendingPathComponent("AgentRuns", isDirectory: true)
        let run = heavyRun()
        let writer = AgentRunPersistenceDiskWriter(rootURL: rootURL, chunkSize: 200)
        try writer.write([run])
        let detailURL = rootURL.appendingPathComponent("Details/\(run.id.uuidString).json")
        let manifestURL = rootURL.appendingPathComponent("ChangedFiles/\(run.id.uuidString)/manifest.json")
        let oldDate = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: detailURL.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: manifestURL.path)

        try writer.write([run])

        #expect(abs(modificationDate(detailURL).timeIntervalSince(oldDate)) < 0.5)
        #expect(abs(modificationDate(manifestURL).timeIntervalSince(oldDate)) < 0.5)
    }

    private func heavyRun() -> AgentRun {
        var run = makeRun(files: (0 ..< 500).map { changedFile("Sources/File\($0).swift") })
        run.events = (0 ..< 40).map { index in
            AgentRunEvent(kind: .transcript, label: "tool", text: "event-payload-\(index)-" + String(repeating: "x", count: 800))
        }
        run.actions = (0 ..< 40).map { index in
            AgentRunActionRecord(kind: .reply, status: .succeeded, message: "action-payload-\(index)-" + String(repeating: "y", count: 600))
        }
        run.verification = AgentVerification(
            status: .failed,
            command: "swift build && swift test",
            output: "verification-payload-" + String(repeating: "z", count: 8_000),
            updatedAt: Date()
        )
        return run
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
        AgentChangedFile(path: path, oldPath: nil, status: .modified, additions: 1, deletions: 0, isBinary: false)
    }

    private func tempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }
}

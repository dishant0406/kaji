import Foundation
import Testing

@testable import Droid

@MainActor
struct AgentRunStoreTests {
    @Test
    func startCreatesExactPaneRun() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()

        store.start(providerID: "codex", paneID: paneID, projectID: projectID, worktreeID: worktreeID)

        #expect(store.runs.count == 1)
        #expect(store.runs.first?.providerID == "codex")
        #expect(store.runs.first?.paneID == paneID)
        #expect(store.runs.first?.projectID == projectID)
        #expect(store.runs.first?.worktreeID == worktreeID)
        #expect(store.runs.first?.status == .running)
        #expect(store.runs.first?.sourceConfidence == .exactPane)
        store.reset()
    }

    @Test
    func sameProviderCanRunInDifferentWorktrees() {
        let store = AgentRunStore.shared
        store.reset()

        let projectID = UUID()
        let firstWorktreeID = UUID()
        let secondWorktreeID = UUID()
        let firstPaneID = UUID()
        let secondPaneID = UUID()

        store.start(providerID: "opencode", paneID: firstPaneID, projectID: projectID, worktreeID: firstWorktreeID)
        store.start(providerID: "opencode", paneID: secondPaneID, projectID: projectID, worktreeID: secondWorktreeID)

        #expect(store.runs.count == 2)
        #expect(store.runs.contains { $0.paneID == firstPaneID && $0.status == .running })
        #expect(store.runs.contains { $0.paneID == secondPaneID && $0.status == .running })
        store.reset()
    }

    @Test
    func sameProviderCanRunInSameWorktreeWithSharedAttribution() {
        let store = AgentRunStore.shared
        store.reset()

        let projectID = UUID()
        let worktreeID = UUID()
        let firstPaneID = UUID()
        let secondPaneID = UUID()

        store.start(providerID: "opencode", paneID: firstPaneID, projectID: projectID, worktreeID: worktreeID)
        store.start(providerID: "opencode", paneID: secondPaneID, projectID: projectID, worktreeID: worktreeID)

        #expect(store.runs.count == 2)
        #expect(store.runs.allSatisfy { $0.status == .running })
        #expect(store.runs.allSatisfy { $0.changedFilesAttribution == .sharedWorktree })
        store.reset()
    }

    @Test
    func stopByPaneCompletesOnlyMatchingRun() {
        let store = AgentRunStore.shared
        store.reset()

        let projectID = UUID()
        let firstPaneID = UUID()
        let secondPaneID = UUID()

        store.start(providerID: "claude", paneID: firstPaneID, projectID: projectID, worktreeID: UUID())
        store.start(providerID: "claude", paneID: secondPaneID, projectID: projectID, worktreeID: UUID())

        store.stop(paneID: firstPaneID)

        #expect(store.runs.first { $0.paneID == firstPaneID }?.status == .completed)
        #expect(store.runs.first { $0.paneID == secondPaneID }?.status == .running)
        store.reset()
    }

    @Test
    func stopByPanePrefersOpenRunWhenPaneHasHistory() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()

        store.start(providerID: "opencode", paneID: paneID, projectID: projectID, worktreeID: worktreeID)
        store.stop(paneID: paneID)
        let firstRunID = store.runs[0].id
        store.start(providerID: "opencode", paneID: paneID, projectID: projectID, worktreeID: worktreeID)
        let secondRunID = store.runs[0].id

        store.complete(providerID: "opencode", paneID: paneID, message: "Done")

        #expect(store.run(id: firstRunID)?.status == .completed)
        #expect(store.run(id: secondRunID)?.status == .completed)
        #expect(store.run(id: secondRunID)?.events.last?.text == "Done")
        store.reset()
    }

    @Test
    func lateStartAfterCompletionDoesNotReopenRun() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()

        store.start(providerID: "opencode", paneID: paneID, projectID: projectID, worktreeID: worktreeID)
        store.complete(providerID: "opencode", paneID: paneID, message: "Done")
        store.start(providerID: "opencode", paneID: paneID, projectID: projectID, worktreeID: worktreeID)

        #expect(store.runs.count == 1)
        #expect(store.runs.first?.status == .completed)
        store.reset()
    }

    @Test
    func completionAfterStopPreventsLateReopen() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()

        store.start(providerID: "opencode", paneID: paneID, projectID: projectID, worktreeID: worktreeID)
        store.stop(paneID: paneID)
        store.complete(providerID: "opencode", paneID: paneID, message: "Done")
        store.start(providerID: "opencode", paneID: paneID, projectID: projectID, worktreeID: worktreeID)

        #expect(store.runs.count == 1)
        #expect(store.runs.first?.status == .completed)
        #expect(store.runs.first?.events.last?.kind == .completed)
        store.reset()
    }

    @Test
    func contextCompletionClosesMatchingRunWithoutPaneID() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()

        store.start(providerID: "codex", paneID: paneID, projectID: projectID, worktreeID: worktreeID)
        store.complete(providerID: "codex", projectID: projectID, worktreeID: worktreeID, message: "Done")

        #expect(store.runs.first?.status == .completed)
        #expect(store.runs.first?.events.last?.kind == .completed)
        store.reset()
    }

    @Test
    func transcriptEventsAttachToMatchingRun() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        store.start(providerID: "codex", paneID: paneID, projectID: UUID(), worktreeID: UUID())

        store.appendTranscript(providerID: "codex", paneID: paneID, kind: "tool", text: "Read Package.swift")

        #expect(store.runs.first?.events.last?.kind == .transcript)
        #expect(store.runs.first?.events.last?.label == "tool")
        #expect(store.runs.first?.events.last?.text == "Read Package.swift")
        #expect(store.runs.first?.status == .running)
        store.reset()
    }

    @Test
    func attentionTranscriptMarksRunNeedsAttention() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        store.start(providerID: "opencode", paneID: paneID, projectID: UUID(), worktreeID: UUID())

        store.appendTranscript(providerID: "opencode", paneID: paneID, kind: "attention", text: "Permission requested")

        #expect(store.runs.first?.status == .needsAttention)
        #expect(store.runs.first?.events.last?.kind == .attention)
        store.reset()
    }

    @Test
    func changedFilesAttachToMatchingRun() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        store.start(providerID: "codex", paneID: paneID, projectID: UUID(), worktreeID: UUID())

        store.setChangedFiles(
            providerID: "codex",
            paneID: paneID,
            files: [.init(
                path: "Droid/Services/AgentRunStore.swift",
                oldPath: nil,
                status: .modified,
                additions: 4,
                deletions: 1,
                isBinary: false
            )],
            attribution: .worktreeSnapshot
        )

        #expect(store.runs.first?.changedFiles.count == 1)
        #expect(store.runs.first?.changedFilesAttribution == .worktreeSnapshot)
        #expect(store.runs.first?.events.last?.kind == .fileChange)
        store.reset()
    }

    @Test
    func verificationStateUpdatesMatchingRun() {
        let store = AgentRunStore.shared
        store.reset()

        let paneID = UUID()
        store.start(providerID: "codex", paneID: paneID, projectID: UUID(), worktreeID: UUID())
        let runID = store.runs[0].id

        store.startVerification(runID: runID, command: "swift build && swift test")
        #expect(store.runs.first?.verification.status == .running)
        #expect(store.runs.first?.verification.command == "swift build && swift test")

        store.finishVerification(runID: runID, status: .passed, output: "ok")
        #expect(store.runs.first?.verification.status == .passed)
        #expect(store.runs.first?.verification.output == "ok")
        store.reset()
    }

    @Test
    func persistsCompletedRunsAcrossStoreInstances() throws {
        let fileStore = makeFileStore()
        let store = AgentRunStore(fileStore: fileStore)
        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()

        store.start(providerID: "codex", paneID: paneID, projectID: projectID, worktreeID: worktreeID, worktreePath: "/tmp/muxy")
        store.complete(providerID: "codex", paneID: paneID, message: "Done")

        let reloaded = AgentRunStore(fileStore: fileStore)

        #expect(reloaded.runs.count == 1)
        #expect(reloaded.runs.first?.providerID == "codex")
        #expect(reloaded.runs.first?.status == .completed)
        #expect(reloaded.runs.first?.worktreePath == "/tmp/muxy")
        #expect(reloaded.runs.first?.events.last?.text == "Done")
    }

    @Test
    func persistedOpenRunsReloadAsStale() throws {
        let fileStore = makeFileStore()
        let store = AgentRunStore(fileStore: fileStore)
        let paneID = UUID()

        store.start(providerID: "opencode", paneID: paneID, projectID: UUID(), worktreeID: UUID())
        store.startVerification(runID: try #require(store.runs.first?.id), command: "swift test")

        let reloaded = AgentRunStore(fileStore: fileStore)

        #expect(reloaded.runs.first?.status == .stale)
        #expect(reloaded.runs.first?.verification.status == .unavailable)
        #expect(reloaded.runs.first?.verification.output == "Verification was interrupted.")
    }

    private func makeFileStore() -> CodableFileStore<[AgentRun]> {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return CodableFileStore(fileURL: directory.appendingPathComponent("agent-runs.json"))
    }
}

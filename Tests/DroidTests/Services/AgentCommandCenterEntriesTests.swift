import Foundation
import Testing

@testable import Droid

@MainActor
struct AgentCommandCenterEntriesTests {
    @Test
    func runningRunExposesAllKeyboardActions() {
        let file = AgentChangedFile(path: "Droid/App.swift", oldPath: nil, status: .modified, additions: 4, deletions: 1, isBinary: false)
        let item = item(changedFiles: [file], status: .running, sessionID: "session-1")

        let entries = AgentCommandCenterEntries.entries(for: [item])
        let actions = entries.map(\.action)

        #expect(actions == [.jump, .reply, .stop, .newRun, .resume, .verify, .openFile(file), .openDiff(file)])
        #expect(entries.map(\.category) == ["Navigate", "Control", "Control", "Session", "Session", "Review", "Files", "Files"])
    }

    @Test
    func entriesAreGroupedByAgentRun() {
        let first = item(changedFiles: [], status: .running, sessionID: nil)
        let second = item(changedFiles: [], status: .completed, sessionID: nil)

        let sections = AgentCommandCenterEntries.sections(for: AgentCommandCenterEntries.entries(for: [first, second]))

        #expect(sections.count == 2)
        #expect(sections[0].id == first.id)
        #expect(sections[0].entries.map(\.action) == [.jump, .reply, .stop, .newRun])
        #expect(sections[1].id == second.id)
        #expect(sections[1].entries.map(\.action) == [.jump, .reply, .newRun])
    }

    @Test
    func deletedFilesExposeDiffButNotOpenFile() {
        let file = AgentChangedFile(path: "Droid/Old.swift", oldPath: nil, status: .deleted, additions: 0, deletions: 8, isBinary: false)
        let item = item(changedFiles: [file], status: .completed, sessionID: nil)

        let actions = AgentCommandCenterEntries.entries(for: [item]).map(\.action)

        #expect(actions.contains(.openDiff(file)))
        #expect(!actions.contains(.openFile(file)))
    }

    @Test
    func completedRunWithoutEvidenceShowsJumpReplyAndNewRun() {
        let item = item(changedFiles: [], status: .completed, sessionID: nil)

        let actions = AgentCommandCenterEntries.entries(for: [item]).map(\.action)

        #expect(actions == [.jump, .reply, .newRun])
    }

    private func item(
        changedFiles: [AgentChangedFile],
        status: AgentMissionControlStatus,
        sessionID: String?
    ) -> AgentMissionControlItem {
        AgentMissionControlItem(
            id: UUID().uuidString,
            runID: UUID(),
            providerID: "codex",
            providerName: "Codex",
            providerIconName: "codex",
            sessionID: sessionID,
            title: "Codex",
            detail: "muxy / main",
            status: status,
            timestamp: Date(),
            paneID: UUID(),
            notificationID: nil,
            transcriptEntries: [],
            changedFiles: changedFiles,
            changedFilesAttribution: changedFiles.isEmpty ? .none : .worktreeSnapshot,
            verification: .notStarted
        )
    }
}

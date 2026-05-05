import Foundation
import Testing

@testable import Droid

@Suite("ParentAgentTaskStore assignments")
@MainActor
struct ParentAgentTaskStoreAssignmentTests {
    @Test("creates assignment and attaches run metadata")
    func createsAssignmentAndAttachesRun() throws {
        let store = makeStore()
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let task = store.start(prompt: "fix parent agent")
        let assignment = try #require(store.createAssignment(
            taskID: task.id,
            title: "Fix tab behavior",
            prompt: "Make Droid a tab",
            project: project,
            worktree: worktree
        ))
        let runID = UUID()
        let paneID = UUID()

        store.attachRun(
            taskID: task.id,
            assignmentID: assignment.id,
            run: ParentAgentAssignmentRunAttachment(
                runID: runID,
                paneID: paneID,
                providerID: AskProvider.codex.rawValue,
                modelID: "gpt-5.5"
            )
        )

        let updated = try #require(store.assignment(taskID: task.id, assignmentID: assignment.id))
        #expect(updated.runID == runID)
        #expect(updated.paneID == paneID)
        #expect(updated.providerID == AskProvider.codex.rawValue)
        #expect(updated.modelID == "gpt-5.5")
        #expect(updated.status == .running)
        #expect(store.tasks[0].childRunIDs == [runID])
    }

    @Test("completion stores final artifacts and status")
    func completionStoresArtifacts() throws {
        let store = makeStore()
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let task = store.start(prompt: "fix parent agent")
        let assignment = try #require(store.createAssignment(
            taskID: task.id,
            title: "Fix tab behavior",
            prompt: "Make Droid a tab",
            project: project,
            worktree: worktree
        ))
        let changedFile = ParentAgentChangedFileContext(
            path: "Droid/Views/MainWindow.swift",
            oldPath: nil,
            status: "modified",
            additions: 1,
            deletions: 0,
            isBinary: false
        )

        store.completeAssignment(
            taskID: task.id,
            assignmentID: assignment.id,
            completion: ParentAgentAssignmentCompletion(
                summary: "Implemented tab behavior.",
                changedFiles: [changedFile],
                verification: ParentAgentVerificationContext(status: "passed", command: "swift build", output: "ok"),
                status: .completed
            )
        )

        let updated = try #require(store.assignment(taskID: task.id, assignmentID: assignment.id))
        #expect(updated.status == .completed)
        #expect(updated.finalSummary == "Implemented tab behavior.")
        #expect(updated.changedFiles == [changedFile])
        #expect(updated.verification?.status == "passed")
    }

    @Test("attention updates assignment status and detail")
    func attentionUpdatesAssignment() throws {
        let store = makeStore()
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let task = store.start(prompt: "fix parent agent")
        let assignment = try #require(store.createAssignment(
            taskID: task.id,
            title: "Fix tab behavior",
            prompt: "Make Droid a tab",
            project: project,
            worktree: worktree
        ))
        let attention = ParentAgentAttention(
            kind: .permission,
            providerID: "opencode",
            title: "OpenCode needs permission",
            detail: "Allow once",
            suggestedAction: "Approve in terminal"
        )

        store.recordAttention(taskID: task.id, assignmentID: assignment.id, attention: attention)

        let updated = try #require(store.assignment(taskID: task.id, assignmentID: assignment.id))
        #expect(updated.status == .waitingForUser)
        #expect(updated.attention == attention)
        #expect(updated.lastEvent == "OpenCode needs permission: Allow once")
    }

    private func makeStore() -> ParentAgentTaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return ParentAgentTaskStore(persistence: ParentAgentTaskPersistence(store: CodableFileStore(fileURL: url)))
    }
}

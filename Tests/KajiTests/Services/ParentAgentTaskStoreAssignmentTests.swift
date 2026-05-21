import Foundation
import Testing

@testable import Kaji

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
            prompt: "Make Kaji a tab",
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
            prompt: "Make Kaji a tab",
            project: project,
            worktree: worktree
        ))
        let changedFile = ParentAgentChangedFileContext(
            path: "Kaji/Views/MainWindow.swift",
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
            prompt: "Make Kaji a tab",
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

    @Test("store bounds retained task history")
    func storeBoundsRetainedTaskHistory() {
        let store = makeStore()

        for index in 0 ..< 60 {
            _ = store.start(prompt: "task \(index)")
        }

        #expect(store.tasks.count <= 40)
    }

    @Test("store bounds timeline and detail retention")
    func storeBoundsTimelineAndDetailRetention() throws {
        let store = makeStore()
        let task = store.start(prompt: "long task")
        let detail = String(repeating: "x", count: 40_000)

        for index in 0 ..< 200 {
            store.append(taskID: task.id, kind: .event, title: "event \(index)", detail: detail)
        }

        let updated = try #require(store.tasks.first { $0.id == task.id })
        #expect(updated.timeline.count <= 160)
        #expect(updated.timeline.allSatisfy { $0.detail.count <= 30_000 })
    }

    @Test("streaming deltas are not persisted until flushed")
    func streamingDeltasAreDebounced() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let persistence = ParentAgentTaskPersistence(store: CodableFileStore(fileURL: url))
        let store = ParentAgentTaskStore(persistence: persistence, streamingSaveInterval: .seconds(60))
        let task = store.start(prompt: "stream")

        store.appendAssistantDelta(taskID: task.id, text: "hello")
        store.appendAssistantDelta(taskID: task.id, text: " world")

        let beforeFlush = try #require(persistence.load()?.tasks.first { $0.id == task.id })
        #expect(beforeFlush.timeline.count == 1)

        store.flushStreamingSave()

        let afterFlush = try #require(persistence.load()?.tasks.first { $0.id == task.id })
        #expect(afterFlush.timeline.last?.detail == "hello world")
    }

    private func makeStore() -> ParentAgentTaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return ParentAgentTaskStore(persistence: ParentAgentTaskPersistence(store: CodableFileStore(fileURL: url)))
    }
}

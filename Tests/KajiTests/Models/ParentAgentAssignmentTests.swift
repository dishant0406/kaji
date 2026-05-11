import Foundation
import Testing

@testable import Kaji

@Suite("ParentAgentAssignment")
struct ParentAgentAssignmentTests {
    @Test("new assignment stores explicit task ownership")
    func assignmentStoresTaskOwnership() {
        let project = Project(name: "muxy", path: "/tmp/muxy")
        let worktree = Worktree(name: "main", path: "/tmp/muxy", isPrimary: true)
        let taskID = UUID()

        let assignment = ParentAgentAssignment(
            parentTaskID: taskID,
            title: "Fix tab behavior",
            prompt: "Make Kaji a tab",
            project: project,
            worktree: worktree,
            isolation: .sharedWorktree
        )

        #expect(assignment.parentTaskID == taskID)
        #expect(assignment.title == "Fix tab behavior")
        #expect(assignment.projectID == project.id)
        #expect(assignment.worktreeID == worktree.id)
        #expect(assignment.status == .planned)
        #expect(assignment.mode == .fresh)
    }

    @Test("ParentAgentTask decodes legacy tasks without assignments")
    func legacyTaskDecodesWithoutAssignments() throws {
        let taskID = UUID()
        let itemID = UUID()
        let createdAt = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000))
        let json = """
        {
          "id": "\(taskID.uuidString)",
          "prompt": "hello",
          "status": "completed",
          "timeline": [{
            "id": "\(itemID.uuidString)",
            "kind": "user",
            "title": "You",
            "detail": "hello",
            "attachments": [],
            "isComplete": true,
            "createdAt": "\(createdAt)"
          }],
          "childRunIDs": [],
          "spawnFingerprints": [],
          "pendingQuestionOptions": [],
          "createdAt": "\(createdAt)",
          "updatedAt": "\(createdAt)"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let task = try decoder.decode(ParentAgentTask.self, from: Data(json.utf8))

        #expect(task.id == taskID)
        #expect(task.assignments.isEmpty)
    }

    @Test("assignment status exposes continuation and replacement eligibility")
    func statusEligibility() {
        #expect(ParentAgentAssignmentStatus.running.canContinue)
        #expect(ParentAgentAssignmentStatus.waitingForUser.canContinue)
        #expect(!ParentAgentAssignmentStatus.completed.canContinue)
        #expect(ParentAgentAssignmentStatus.incomplete.canReplace)
        #expect(ParentAgentAssignmentStatus.stale.canReplace)
        #expect(!ParentAgentAssignmentStatus.running.canReplace)
    }
}

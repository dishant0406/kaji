import Foundation
import Testing

@testable import Droid

@Suite("ParentAgentSubagentPolicy")
struct ParentAgentSubagentPolicyTests {
    @Test("blocks duplicate active assignment")
    func blocksDuplicateActiveAssignment() {
        let projectID = UUID()
        let worktreeID = UUID()
        let existing = assignment(prompt: "fix sidebar", projectID: projectID, worktreeID: worktreeID, status: .running)
        let request = ParentAgentSubagentRequest(
            prompt: "fix sidebar",
            projectID: projectID,
            worktreeID: worktreeID,
            isolation: .sharedWorktree
        )

        let decision = ParentAgentSubagentPolicy.decideSpawn(request: request, assignments: [existing])

        #expect(decision == .blocked(
            "A subagent assignment is already working on this same task.",
            assignmentID: existing.id
        ))
    }

    @Test("blocks retry wording for waiting assignment")
    func blocksRetryWordingForWaitingAssignment() {
        let projectID = UUID()
        let worktreeID = UUID()
        let existing = assignment(
            prompt: "Update multer dependency in zerocarbonbackend",
            projectID: projectID,
            worktreeID: worktreeID,
            status: .waitingForUser
        )
        let request = ParentAgentSubagentRequest(
            prompt: "Retry updating multer dependency. The current attempt is waiting for approval.",
            projectID: projectID,
            worktreeID: worktreeID,
            isolation: .isolatedWorktree
        )

        let decision = ParentAgentSubagentPolicy.decideSpawn(request: request, assignments: [existing])

        #expect(decision == .blocked(
            "A subagent assignment is already working on this same task.",
            assignmentID: existing.id
        ))
    }

    @Test("blocks shared-worktree parallel write assignment")
    func blocksSharedWorktreeParallelWriteAssignment() {
        let projectID = UUID()
        let worktreeID = UUID()
        let existing = assignment(prompt: "fix sidebar", projectID: projectID, worktreeID: worktreeID, status: .running)
        let request = ParentAgentSubagentRequest(
            prompt: "implement tab behavior",
            projectID: projectID,
            worktreeID: worktreeID,
            isolation: .sharedWorktree
        )

        let decision = ParentAgentSubagentPolicy.decideSpawn(request: request, assignments: [existing])

        #expect(decision == .requiresIsolation(
            "Another write-capable subagent is active in this worktree. Use isolatedWorktree or wait for it to finish.",
            assignmentID: existing.id
        ))
    }

    @Test("allows read-only shared-worktree assignment")
    func allowsReadOnlySharedWorktreeAssignment() {
        let projectID = UUID()
        let worktreeID = UUID()
        let existing = assignment(prompt: "fix sidebar", projectID: projectID, worktreeID: worktreeID, status: .running)
        let request = ParentAgentSubagentRequest(
            prompt: "review only the tab behavior",
            projectID: projectID,
            worktreeID: worktreeID,
            isolation: .sharedWorktree
        )

        let decision = ParentAgentSubagentPolicy.decideSpawn(request: request, assignments: [existing])

        #expect(decision == .allowed)
    }

    @Test("allows isolated write assignment with active shared worktree writer")
    func allowsIsolatedWriteAssignment() {
        let projectID = UUID()
        let existingWorktreeID = UUID()
        let isolatedWorktreeID = UUID()
        let existing = assignment(prompt: "fix sidebar", projectID: projectID, worktreeID: existingWorktreeID, status: .running)
        let request = ParentAgentSubagentRequest(
            prompt: "implement tab behavior",
            projectID: projectID,
            worktreeID: isolatedWorktreeID,
            isolation: .isolatedWorktree
        )

        let decision = ParentAgentSubagentPolicy.decideSpawn(request: request, assignments: [existing])

        #expect(decision == .allowed)
    }

    private func assignment(
        prompt: String,
        projectID: UUID,
        worktreeID: UUID,
        status: ParentAgentAssignmentStatus
    ) -> ParentAgentAssignment {
        var assignment = ParentAgentAssignment(
            parentTaskID: UUID(),
            title: prompt,
            prompt: prompt,
            project: Project(name: "muxy", path: "/tmp/muxy"),
            worktree: Worktree(id: worktreeID, name: "main", path: "/tmp/muxy", isPrimary: true)
        )
        assignment.projectID = projectID
        assignment.worktreeID = worktreeID
        assignment.status = status
        return assignment
    }
}

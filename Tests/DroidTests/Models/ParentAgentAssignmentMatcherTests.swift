import Foundation
import Testing

@testable import Droid

@Suite("ParentAgentAssignmentMatcher")
struct ParentAgentAssignmentMatcherTests {
    @Test("matches retry wording to existing multer assignment")
    func matchesRetryWording() {
        let assignment = assignment(title: "Update multer dependency in zerocarbonbackend")

        #expect(ParentAgentAssignmentMatcher.matches(
            task: "Retry updating the multer dependency in zerocarbonbackend to a newer version. The current attempt is waiting for approval.",
            assignment: assignment
        ))
    }

    @Test("does not match unrelated port and multer tasks")
    func doesNotMatchUnrelatedTasks() {
        let assignment = assignment(title: "Set default port to 3000 in zerocarbonbackend")

        #expect(!ParentAgentAssignmentMatcher.matches(
            task: "Update the multer dependency in zerocarbonbackend to a newer version",
            assignment: assignment
        ))
    }

    private func assignment(title: String) -> ParentAgentAssignment {
        ParentAgentAssignment(
            parentTaskID: UUID(),
            title: title,
            prompt: title,
            project: Project(name: "zerocarbonbackend", path: "/tmp/zerocarbonbackend"),
            worktree: Worktree(name: "main", path: "/tmp/zerocarbonbackend", isPrimary: true)
        )
    }
}

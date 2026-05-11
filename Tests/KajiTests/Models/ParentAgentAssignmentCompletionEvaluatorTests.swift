import Testing

@testable import Kaji

@Suite("ParentAgentAssignmentCompletionEvaluator")
struct ParentAgentAssignmentCompletionEvaluatorTests {
    @Test("completed run with final summary is completed")
    func completedRunWithFinalSummary() {
        let status = ParentAgentAssignmentCompletionEvaluator.status(
            assignmentStatus: .running,
            runStatus: .completed,
            finalSummary: "Done",
            changedFiles: []
        )

        #expect(status == .completed)
    }

    @Test("completed run with changed files is completed")
    func completedRunWithChangedFiles() {
        let status = ParentAgentAssignmentCompletionEvaluator.status(
            assignmentStatus: .running,
            runStatus: .completed,
            finalSummary: nil,
            changedFiles: [changedFile]
        )

        #expect(status == .completed)
    }

    @Test("completed run without useful evidence is incomplete")
    func completedRunWithoutEvidence() {
        let status = ParentAgentAssignmentCompletionEvaluator.status(
            assignmentStatus: .running,
            runStatus: .completed,
            finalSummary: nil,
            changedFiles: []
        )

        #expect(status == .incomplete)
    }

    @Test("stopped assignment remains stopped even if run closed")
    func stoppedAssignmentWins() {
        let status = ParentAgentAssignmentCompletionEvaluator.status(
            assignmentStatus: .stopped,
            runStatus: .completed,
            finalSummary: nil,
            changedFiles: []
        )

        #expect(status == .stopped)
    }

    private var changedFile: ParentAgentChangedFileContext {
        ParentAgentChangedFileContext(
            path: "Kaji/Views/MainWindow.swift",
            oldPath: nil,
            status: "modified",
            additions: 1,
            deletions: 0,
            isBinary: false
        )
    }
}

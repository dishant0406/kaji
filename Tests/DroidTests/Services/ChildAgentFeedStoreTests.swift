import Foundation
import Testing

@testable import Droid

@Suite("ChildAgentFeedStore")
@MainActor
struct ChildAgentFeedStoreTests {
    @Test("terminal snapshots retain enough visible screen output")
    func terminalSnapshotsRetainVisibleOutput() {
        let runID = UUID()
        let lines = (1...30).map { "line \($0)" }.joined(separator: "\n")

        ChildAgentFeedStore.shared.append(runID: runID, kind: .terminal, text: lines)

        let output = ChildAgentFeedStore.shared.terminalOutput(runID: runID)
        #expect(output?.contains("line 1") == true)
        #expect(output?.contains("line 30") == true)
        #expect(output?.split(separator: "\n").count == 30)
    }
}

import Foundation
import Testing

@testable import Droid

struct AgentMissionControlSectionBuilderTests {
    @Test
    func sectionsFollowOperationalPriority() {
        let sections = AgentMissionControlSectionBuilder.sections(for: [
            item(id: "run:done", status: .completed),
            item(id: "notification:done", status: .completed),
            item(id: "run:failed", status: .failed),
            item(id: "run:running", status: .running),
            item(id: "run:attention", status: .needsAttention),
        ])

        #expect(sections.map(\.kind) == [.needsAttention, .running, .failed, .completed, .notifications])
        #expect(sections.map { $0.items.first?.id } == [
            "run:attention",
            "run:running",
            "run:failed",
            "run:done",
            "notification:done",
        ])
    }

    @Test
    func notificationRowsStayInFallbackSectionRegardlessOfStatus() {
        let sections = AgentMissionControlSectionBuilder.sections(for: [
            item(id: "notification:question", status: .needsAttention),
            item(id: "notification:failed", status: .failed),
        ])

        #expect(sections.count == 1)
        #expect(sections.first?.kind == .notifications)
        #expect(sections.first?.items.map(\.id) == ["notification:question", "notification:failed"])
    }

    private func item(id: String, status: AgentMissionControlStatus) -> AgentMissionControlItem {
        AgentMissionControlItem(
            id: id,
            runID: nil,
            providerID: "codex",
            providerName: "Codex",
            providerIconName: "codex",
            title: id,
            detail: "muxy / main",
            status: status,
            timestamp: Date(),
            paneID: UUID(),
            notificationID: nil,
            transcriptEntries: [],
            changedFiles: [],
            changedFilesAttribution: .none,
            verification: .notStarted
        )
    }
}

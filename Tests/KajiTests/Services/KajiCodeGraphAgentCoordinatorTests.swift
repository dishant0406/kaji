import Foundation
import Testing

@testable import Kaji

@Suite("KajiCodeGraphAgentCoordinator")
@MainActor
struct KajiCodeGraphAgentCoordinatorTests {
    @Test("coordinator bounds retained graph agent sessions")
    func coordinatorBoundsRetainedSessions() {
        let coordinator = KajiCodeGraphAgentCoordinator(maxSessions: 2)
        let first = makeSession(key: "one")
        let second = makeSession(key: "two")
        let third = makeSession(key: "three")

        coordinator.retain(first)
        coordinator.retain(second)
        coordinator.retain(third)

        #expect(coordinator.sessions.map(\.key) == ["three", "two"])
        #expect(!coordinator.visibleKeys.contains("one"))
        #expect(coordinator.selectedSessionID == third.id)
    }

    private func makeSession(key: String) -> KajiCodeGraphAgentSession {
        KajiCodeGraphAgentSession(
            key: key,
            title: key,
            subtitle: "Test",
            controller: ParentAgentController(store: ParentAgentTaskStore(persistence: tempPersistence())),
            store: ParentAgentTaskStore(persistence: tempPersistence())
        )
    }

    private func tempPersistence() -> ParentAgentTaskPersistence {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return ParentAgentTaskPersistence(store: CodableFileStore(fileURL: url))
    }
}

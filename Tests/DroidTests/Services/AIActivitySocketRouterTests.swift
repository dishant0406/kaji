import Foundation
import Testing

@testable import Droid

@MainActor
struct AIActivitySocketRouterTests {
    @Test
    func explicitContextStartsAndStopsActivity() {
        let store = AIActivityStore.shared
        store.reset()

        let paneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        let payloadBody = "\(projectID.uuidString),\(worktreeID.uuidString)"

        let handledStart = AIActivitySocketRouter.handle(
            .init(
                type: "opencode_activity",
                title: "start",
                body: payloadBody,
                paneIDString: paneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handledStart)
        #expect(store.activitiesByPaneID[paneID]?.projectID == projectID)
        #expect(store.activitiesByPaneID[paneID]?.worktreeID == worktreeID)

        let handledStop = AIActivitySocketRouter.handle(
            .init(
                type: "opencode_activity",
                title: "stop",
                body: payloadBody,
                paneIDString: paneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handledStop)
        #expect(store.activitiesByPaneID[paneID] == nil)
    }

    @Test
    func explicitContextStopsActivityWhenPaneLookupIsUnavailable() {
        let store = AIActivityStore.shared
        store.reset()

        let startedPaneID = UUID()
        let stoppedPaneID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        let payloadBody = "\(projectID.uuidString),\(worktreeID.uuidString)"

        store.start(
            providerID: "claude",
            paneID: startedPaneID,
            projectID: projectID,
            worktreeID: worktreeID
        )

        let handledStop = AIActivitySocketRouter.handle(
            .init(
                type: "claude_activity",
                title: "stop",
                body: payloadBody,
                paneIDString: stoppedPaneID.uuidString
            ),
            appState: nil,
            worktreeStore: nil
        )

        #expect(handledStop)
        #expect(!store.hasActiveAgent(projectID: projectID))
    }
}

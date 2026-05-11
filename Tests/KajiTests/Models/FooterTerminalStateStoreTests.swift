import Foundation
import Testing

@testable import Kaji

@MainActor
struct FooterTerminalStateStoreTests {
    @Test
    func keepsSeparateTerminalStatePerProject() {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let store = FooterTerminalStateStore()

        let firstState = store.show(projectID: firstProjectID, projectPath: "/tmp/first")
        let secondState = store.show(projectID: secondProjectID, projectPath: "/tmp/second")

        #expect(firstState.projectPath == "/tmp/first")
        #expect(secondState.projectPath == "/tmp/second")
        #expect(store.state(for: firstProjectID)?.id == firstState.id)
        #expect(store.state(for: secondProjectID)?.id == secondState.id)
        #expect(store.isVisible(for: firstProjectID))
        #expect(store.isVisible(for: secondProjectID))
    }

    @Test
    func collapsingOneProjectDoesNotCollapseAnother() {
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let store = FooterTerminalStateStore()

        _ = store.show(projectID: firstProjectID, projectPath: "/tmp/first")
        _ = store.show(projectID: secondProjectID, projectPath: "/tmp/second")
        store.collapse(projectID: firstProjectID)

        #expect(!store.isVisible(for: firstProjectID))
        #expect(store.isVisible(for: secondProjectID))
        #expect(store.state(for: firstProjectID) != nil)
    }
}

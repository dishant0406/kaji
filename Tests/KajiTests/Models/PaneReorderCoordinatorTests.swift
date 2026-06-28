import CoreGraphics
import Foundation
import Testing

@testable import Kaji

@Suite("PaneReorderCoordinator")
@MainActor
struct PaneReorderCoordinatorTests {
    @Test("center resolves a pane swap target")
    func centerResolvesSwapTarget() {
        let projectID = UUID()
        let sourceAreaID = UUID()
        let targetAreaID = UUID()
        let coordinator = PaneReorderCoordinator()

        coordinator.setAreaFrames([targetAreaID: CGRect(x: 0, y: 0, width: 400, height: 240)], forProject: projectID)
        coordinator.beginReorder(sourceAreaID: sourceAreaID, projectID: projectID)
        coordinator.updatePosition(CGPoint(x: 200, y: 120))

        #expect(coordinator.hoveredAreaID == targetAreaID)
        #expect(coordinator.hoveredZone == .center)
    }

    @Test("nearest edge resolves a pane split target")
    func nearestEdgeWins() {
        let projectID = UUID()
        let sourceAreaID = UUID()
        let targetAreaID = UUID()
        let coordinator = PaneReorderCoordinator()

        coordinator.setAreaFrames([targetAreaID: CGRect(x: 0, y: 0, width: 400, height: 240)], forProject: projectID)
        coordinator.beginReorder(sourceAreaID: sourceAreaID, projectID: projectID)
        coordinator.updatePosition(CGPoint(x: 12, y: 120))

        #expect(coordinator.hoveredAreaID == targetAreaID)
        #expect(coordinator.hoveredZone == .left)
    }
}

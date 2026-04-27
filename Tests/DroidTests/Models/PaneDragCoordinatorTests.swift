import CoreGraphics
import Foundation
import Testing

@testable import Droid

@Suite("PaneDragCoordinator")
@MainActor
struct PaneDragCoordinatorTests {
    @Test("only edge zones are valid pane drop targets")
    func edgeZonesOnly() {
        let projectID = UUID()
        let areaID = UUID()
        let coordinator = PaneDragCoordinator()

        coordinator.setAreaFrames([areaID: CGRect(x: 0, y: 0, width: 400, height: 240)], forProject: projectID)
        coordinator.beginDrag(sourceAreaID: UUID(), projectID: projectID)
        coordinator.updatePosition(CGPoint(x: 200, y: 120))

        #expect(coordinator.hoveredAreaID == nil)
        #expect(coordinator.hoveredZone == nil)
    }

    @Test("nearest edge resolves a pane drop target")
    func nearestEdgeWins() {
        let projectID = UUID()
        let sourceAreaID = UUID()
        let targetAreaID = UUID()
        let coordinator = PaneDragCoordinator()

        coordinator.setAreaFrames([targetAreaID: CGRect(x: 0, y: 0, width: 400, height: 240)], forProject: projectID)
        coordinator.beginDrag(sourceAreaID: sourceAreaID, projectID: projectID)
        coordinator.updatePosition(CGPoint(x: 12, y: 120))

        #expect(coordinator.hoveredAreaID == targetAreaID)
        #expect(coordinator.hoveredZone == .left)
    }
}

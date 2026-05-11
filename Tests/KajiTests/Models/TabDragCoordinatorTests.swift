import CoreGraphics
import Foundation
import Testing

@testable import Kaji

@Suite("TabDragCoordinator")
@MainActor
struct TabDragCoordinatorTests {
    @Test("tab strip frame wins over area edge zones")
    func stripFrameWinsOverEdgeZone() {
        let projectID = UUID()
        let areaID = UUID()
        let tabID = UUID()
        let coordinator = TabDragCoordinator()

        coordinator.setAreaFrames([areaID: CGRect(x: 0, y: 0, width: 400, height: 240)], forProject: projectID)
        coordinator.setStripFrames([areaID: CGRect(x: 0, y: 0, width: 400, height: 36)], forProject: projectID)

        coordinator.beginDrag(tabID: tabID, sourceAreaID: areaID, projectID: projectID)
        coordinator.updatePosition(CGPoint(x: 180, y: 20))

        #expect(coordinator.hoveredAreaID == areaID)
        #expect(coordinator.hoveredZone == .center)
    }

    @Test("area edge zones still resolve outside tab strip")
    func areaEdgeZonesStillResolve() {
        let projectID = UUID()
        let areaID = UUID()
        let tabID = UUID()
        let coordinator = TabDragCoordinator()

        coordinator.setAreaFrames([areaID: CGRect(x: 0, y: 0, width: 400, height: 240)], forProject: projectID)
        coordinator.setStripFrames([areaID: CGRect(x: 0, y: 0, width: 400, height: 36)], forProject: projectID)

        coordinator.beginDrag(tabID: tabID, sourceAreaID: areaID, projectID: projectID)
        coordinator.updatePosition(CGPoint(x: 20, y: 120))

        #expect(coordinator.hoveredAreaID == areaID)
        #expect(coordinator.hoveredZone == .left)
    }
}

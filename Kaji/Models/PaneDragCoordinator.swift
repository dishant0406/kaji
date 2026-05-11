import CoreGraphics
import Foundation

struct PaneMoveRequest {
    let sourceAreaID: UUID
    let targetAreaID: UUID
    let split: SplitPlacement
}

@MainActor
@Observable
final class PaneDragCoordinator {
    struct DragInfo: Equatable {
        let sourceAreaID: UUID
        let projectID: UUID
    }

    struct DropResult {
        let drag: DragInfo
        let zone: DropZone
        let targetAreaID: UUID

        func action(projectID: UUID) -> AppState.Action {
            let split = switch zone {
            case .left:
                SplitPlacement(direction: .horizontal, position: .first)
            case .right:
                SplitPlacement(direction: .horizontal, position: .second)
            case .top:
                SplitPlacement(direction: .vertical, position: .first)
            case .bottom:
                SplitPlacement(direction: .vertical, position: .second)
            case .center:
                SplitPlacement(direction: .horizontal, position: .second)
            }

            return .movePane(
                projectID: projectID,
                request: PaneMoveRequest(
                    sourceAreaID: drag.sourceAreaID,
                    targetAreaID: targetAreaID,
                    split: split
                )
            )
        }
    }

    var activeDrag: DragInfo?
    @ObservationIgnored var globalPosition: CGPoint = .zero
    @ObservationIgnored private var areaFramesByProject: [UUID: [UUID: CGRect]] = [:]
    private(set) var hoveredAreaID: UUID?
    private(set) var hoveredZone: DropZone?

    func setAreaFrames(_ frames: [UUID: CGRect], forProject projectID: UUID) {
        guard areaFramesByProject[projectID] != frames else { return }
        areaFramesByProject[projectID] = frames
        computeHover()
    }

    func beginDrag(sourceAreaID: UUID, projectID: UUID) {
        activeDrag = DragInfo(sourceAreaID: sourceAreaID, projectID: projectID)
    }

    func updatePosition(_ position: CGPoint) {
        globalPosition = position
        computeHover()
    }

    func endDrag() -> DropResult? {
        guard let activeDrag,
              let hoveredAreaID,
              let hoveredZone,
              hoveredAreaID != activeDrag.sourceAreaID
        else {
            cancelDrag()
            return nil
        }

        let result = DropResult(drag: activeDrag, zone: hoveredZone, targetAreaID: hoveredAreaID)
        cancelDrag()
        return result
    }

    func cancelDrag() {
        activeDrag = nil
        globalPosition = .zero
        hoveredAreaID = nil
        hoveredZone = nil
    }

    private func computeHover() {
        guard let projectID = activeDrag?.projectID else {
            hoveredAreaID = nil
            hoveredZone = nil
            return
        }

        let areaFrames = areaFramesByProject[projectID] ?? [:]
        if let match = DropTargetFrameResolver.containingMatch(for: globalPosition, in: areaFrames) {
            let zone = DropTargetFrameResolver.edgeZone(for: globalPosition, in: match.frame)
            hoveredAreaID = zone == nil ? nil : match.areaID
            hoveredZone = zone
            return
        }

        if let match = DropTargetFrameResolver.nearestMatch(for: globalPosition, in: areaFrames, tolerance: 12) {
            let clampedPoint = DropTargetFrameResolver.clamped(globalPosition, to: match.frame)
            hoveredAreaID = match.areaID
            hoveredZone = DropTargetFrameResolver.nearestEdgeZone(for: clampedPoint, in: match.frame)
            return
        }

        hoveredAreaID = nil
        hoveredZone = nil
    }
}

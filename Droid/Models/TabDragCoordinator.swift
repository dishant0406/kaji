import CoreGraphics
import Foundation

enum DragCoordinateSpace {
    static let mainWindow = "main-window-drag-space"
}

enum TabMoveRequest {
    case toArea(tabID: UUID, sourceAreaID: UUID, destinationAreaID: UUID)
    case toNewSplit(tabID: UUID, sourceAreaID: UUID, targetAreaID: UUID, split: SplitPlacement)
}

struct SplitPlacement {
    let direction: SplitDirection
    let position: SplitPosition
}

enum DropZone: Equatable {
    case left
    case right
    case top
    case bottom
    case center
}

@MainActor
@Observable
final class TabDragCoordinator {
    struct DragInfo: Equatable {
        let tabID: UUID
        let sourceAreaID: UUID
        let projectID: UUID
    }

    var activeDrag: DragInfo?
    @ObservationIgnored var globalPosition: CGPoint = .zero
    @ObservationIgnored var areaFramesByProject: [UUID: [UUID: CGRect]] = [:]
    @ObservationIgnored var stripFramesByProject: [UUID: [UUID: CGRect]] = [:]
    private(set) var hoveredAreaID: UUID?
    private(set) var hoveredZone: DropZone?

    func setAreaFrames(_ frames: [UUID: CGRect], forProject projectID: UUID) {
        guard areaFramesByProject[projectID] != frames else { return }
        areaFramesByProject[projectID] = frames
        computeHover()
    }

    func setStripFrames(_ frames: [UUID: CGRect], forProject projectID: UUID) {
        guard stripFramesByProject[projectID] != frames else { return }
        stripFramesByProject[projectID] = frames
        computeHover()
    }

    func beginDrag(tabID: UUID, sourceAreaID: UUID, projectID: UUID) {
        activeDrag = DragInfo(tabID: tabID, sourceAreaID: sourceAreaID, projectID: projectID)
    }

    func updatePosition(_ position: CGPoint) {
        globalPosition = position
        computeHover()
    }

    struct DropResult {
        let drag: DragInfo
        let zone: DropZone
        let targetAreaID: UUID

        func action(projectID: UUID) -> AppState.Action {
            let request: TabMoveRequest = switch zone {
            case .center:
                .toArea(tabID: drag.tabID, sourceAreaID: drag.sourceAreaID, destinationAreaID: targetAreaID)
            case .left:
                .toNewSplit(
                    tabID: drag.tabID, sourceAreaID: drag.sourceAreaID, targetAreaID: targetAreaID,
                    split: SplitPlacement(direction: .horizontal, position: .first)
                )
            case .right:
                .toNewSplit(
                    tabID: drag.tabID, sourceAreaID: drag.sourceAreaID, targetAreaID: targetAreaID,
                    split: SplitPlacement(direction: .horizontal, position: .second)
                )
            case .top:
                .toNewSplit(
                    tabID: drag.tabID, sourceAreaID: drag.sourceAreaID, targetAreaID: targetAreaID,
                    split: SplitPlacement(direction: .vertical, position: .first)
                )
            case .bottom:
                .toNewSplit(
                    tabID: drag.tabID, sourceAreaID: drag.sourceAreaID, targetAreaID: targetAreaID,
                    split: SplitPlacement(direction: .vertical, position: .second)
                )
            }
            return .moveTab(projectID: projectID, request: request)
        }
    }

    func endDrag() -> DropResult? {
        guard let activeDrag, let hoveredAreaID, let hoveredZone else {
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
            updateHover(areaID: nil, zone: nil)
            return
        }

        let stripFrames = stripFramesByProject[projectID] ?? [:]
        if let stripMatch = DropTargetFrameResolver.containingMatch(for: globalPosition, in: stripFrames) {
            updateHover(areaID: stripMatch.areaID, zone: .center)
            return
        }

        let areaFrames = areaFramesByProject[projectID] ?? [:]
        if let containingMatch = DropTargetFrameResolver.containingMatch(for: globalPosition, in: areaFrames) {
            updateHover(
                areaID: containingMatch.areaID,
                zone: DropTargetFrameResolver.zone(for: globalPosition, in: containingMatch.frame)
            )
            return
        }

        guard let nearestMatch = DropTargetFrameResolver.nearestMatch(
            for: globalPosition,
            in: areaFrames,
            tolerance: 8
        ) else {
            updateHover(areaID: nil, zone: nil)
            return
        }
        let clampedPosition = DropTargetFrameResolver.clamped(globalPosition, to: nearestMatch.frame)
        updateHover(
            areaID: nearestMatch.areaID,
            zone: DropTargetFrameResolver.zone(for: clampedPosition, in: nearestMatch.frame)
        )
    }

    private func updateHover(areaID: UUID?, zone: DropZone?) {
        if hoveredAreaID != areaID {
            hoveredAreaID = areaID
        }
        if hoveredZone != zone {
            hoveredZone = zone
        }
    }

}

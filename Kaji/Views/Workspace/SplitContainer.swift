import Bonsplit
import SwiftUI

struct SplitContainer: View {
    private static let minimumPaneSize: CGFloat = 100

    let branch: SplitBranch
    let focusedAreaID: UUID?
    let isActiveProject: Bool
    let showTabStrip: Bool
    let showPaneHeader: Bool
    let showVCSButton: Bool
    let projectID: UUID
    let onFocusArea: (UUID) -> Void
    let onSelectTab: (UUID, UUID) -> Void
    let onCreateTab: (UUID) -> Void
    let onCreateVCSTab: (UUID) -> Void
    let onCloseTab: (UUID, UUID) -> Void
    let onForceCloseTab: (UUID, UUID) -> Void
    let onSplit: (UUID, SplitDirection) -> Void
    let onCloseArea: (UUID) -> Void
    let onDropAction: (TabDragCoordinator.DropResult) -> Void
    let onMoveArea: (PaneReorderCoordinator.DropResult) -> Void

    var body: some View {
        BonsplitSplitView(
            direction: branch.direction.bonsplitDirection,
            ratio: branch.ratio,
            minimumPaneSize: Self.minimumPaneSize,
            onRatioChange: { branch.ratio = $0 },
            first: { child(branch.first) },
            second: { child(branch.second) }
        )
        .accessibilityLabel(branch.direction == .horizontal ? "Horizontal Split" : "Vertical Split")
        .accessibilityValue("Split ratio: \(Int(branch.ratio * 100))%")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = 0.05
            switch direction {
            case .increment:
                branch.ratio = min(branch.ratio + step, 0.85)
            case .decrement:
                branch.ratio = max(branch.ratio - step, 0.15)
            @unknown default:
                break
            }
        }
    }

    private func child(_ node: SplitNode) -> some View {
        PaneNode(
            node: node,
            focusedAreaID: focusedAreaID,
            isActiveProject: isActiveProject,
            showTabStrip: showTabStrip,
            showPaneHeader: showPaneHeader,
            showVCSButton: showVCSButton,
            projectID: projectID,
            onFocusArea: onFocusArea,
            onSelectTab: onSelectTab,
            onCreateTab: onCreateTab,
            onCreateVCSTab: onCreateVCSTab,
            onCloseTab: onCloseTab,
            onForceCloseTab: onForceCloseTab,
            onSplit: onSplit,
            onCloseArea: onCloseArea,
            onDropAction: onDropAction,
            onMoveArea: onMoveArea
        )
    }
}

private extension SplitDirection {
    var bonsplitDirection: BonsplitDirection {
        switch self {
        case .horizontal:
            .horizontal
        case .vertical:
            .vertical
        }
    }
}

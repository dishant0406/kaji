import AppKit
import SwiftUI

struct SplitContainer: View {
    private static let dividerVisualSize: CGFloat = 1
    private static let dividerHitArea: CGFloat = 28

    @State private var dragStartRatio: CGFloat?

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
    let onMoveArea: (PaneDragCoordinator.DropResult) -> Void

    var body: some View {
        GeometryReader { geo in
            let h = branch.direction == .horizontal
            let total = h ? geo.size.width : geo.size.height
            let first = max(0, total * branch.ratio)
            let second = max(0, total * (1 - branch.ratio))

            ZStack(alignment: .topLeading) {
                if h {
                    HStack(spacing: 0) {
                        child(branch.first)
                            .frame(width: first)
                        child(branch.second)
                            .frame(width: second)
                    }
                } else {
                    VStack(spacing: 0) {
                        child(branch.first)
                            .frame(height: first)
                        child(branch.second)
                            .frame(height: second)
                    }
                }

                SplitDividerHandle(
                    horizontal: h,
                    visualSize: Self.dividerVisualSize,
                    onDragStart: { dragStartRatio = branch.ratio },
                    onDrag: { delta in
                        guard total > 0 else { return }
                        let startRatio = dragStartRatio ?? branch.ratio
                        let newPos = total * startRatio + delta
                        branch.ratio = min(max(newPos / total, 0.08), 0.92)
                    }
                )
                .frame(width: h ? Self.dividerHitArea : geo.size.width, height: h ? geo.size.height : Self.dividerHitArea)
                .position(x: h ? first : geo.size.width / 2, y: h ? geo.size.height / 2 : first)
                .zIndex(1000)
                .accessibilityLabel(h ? "Horizontal Split Divider" : "Vertical Split Divider")
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

private struct SplitDividerHandle: NSViewRepresentable {
    let horizontal: Bool
    let visualSize: CGFloat
    let onDragStart: () -> Void
    let onDrag: (CGFloat) -> Void

    func makeNSView(context _: Context) -> SplitDividerHandleView {
        SplitDividerHandleView()
    }

    func updateNSView(_ view: SplitDividerHandleView, context _: Context) {
        view.horizontal = horizontal
        view.visualSize = visualSize
        view.onDragStart = onDragStart
        view.onDrag = onDrag
        view.needsDisplay = true
    }
}

private final class SplitDividerHandleView: NSView {
    var horizontal = true
    var visualSize: CGFloat = 1
    var onDragStart: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    private var dragStart: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = convert(event.locationInWindow, from: nil)
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        onDrag?(horizontal ? point.x - dragStart.x : point.y - dragStart.y)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        let rect = horizontal
            ? NSRect(x: bounds.midX - visualSize / 2, y: 0, width: visualSize, height: bounds.height)
            : NSRect(x: 0, y: bounds.midY - visualSize / 2, width: bounds.width, height: visualSize)
        rect.fill()
    }
}

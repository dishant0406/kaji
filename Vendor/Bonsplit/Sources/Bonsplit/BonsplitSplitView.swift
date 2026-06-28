import AppKit
import SwiftUI

public struct BonsplitSplitView<First: View, Second: View>: NSViewRepresentable {
    private let direction: BonsplitDirection
    private let ratio: CGFloat
    private let minimumPaneSize: CGFloat
    private let onRatioChange: (CGFloat) -> Void
    private let first: First
    private let second: Second

    public init(
        direction: BonsplitDirection,
        ratio: CGFloat,
        minimumPaneSize: CGFloat = 100,
        onRatioChange: @escaping (CGFloat) -> Void,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.direction = direction
        self.ratio = ratio
        self.minimumPaneSize = minimumPaneSize
        self.onRatioChange = onRatioChange
        self.first = first()
        self.second = second()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onRatioChange: onRatioChange)
    }

    public func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.dividerStyle = .thin
        splitView.isVertical = direction == .horizontal
        splitView.delegate = context.coordinator
        splitView.addArrangedSubview(NSHostingView(rootView: first))
        splitView.addArrangedSubview(NSHostingView(rootView: second))
        context.coordinator.apply(direction: direction, ratio: ratio, minimumPaneSize: minimumPaneSize, to: splitView)
        DispatchQueue.main.async {
            context.coordinator.syncRatio(in: splitView)
        }
        return splitView
    }

    public func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.apply(direction: direction, ratio: ratio, minimumPaneSize: minimumPaneSize, to: splitView)
        if let firstHost = splitView.arrangedSubviews[safe: 0] as? NSHostingView<First> {
            firstHost.rootView = first
        }
        if let secondHost = splitView.arrangedSubviews[safe: 1] as? NSHostingView<Second> {
            secondHost.rootView = second
        }
        context.coordinator.syncRatio(in: splitView)
    }

    @MainActor
    public final class Coordinator: NSObject, NSSplitViewDelegate {
        private let onRatioChange: (CGFloat) -> Void
        private var direction: BonsplitDirection = .horizontal
        private var targetRatio: CGFloat = 0.5
        private var minimumPaneSize: CGFloat = 100
        private var isApplying = false

        init(onRatioChange: @escaping (CGFloat) -> Void) {
            self.onRatioChange = onRatioChange
        }

        func apply(direction: BonsplitDirection, ratio: CGFloat, minimumPaneSize: CGFloat, to splitView: NSSplitView) {
            self.direction = direction
            self.targetRatio = ratio.clamped(to: 0.05 ... 0.95)
            self.minimumPaneSize = minimumPaneSize
            splitView.isVertical = direction == .horizontal
        }

        func syncRatio(in splitView: NSSplitView) {
            guard splitView.arrangedSubviews.count == 2 else { return }
            let total = measuredLength(of: splitView.bounds.size)
            guard total > 0 else { return }
            let current = measuredLength(of: splitView.arrangedSubviews[0].frame.size) / total
            guard abs(current - targetRatio) > 0.004 else { return }
            isApplying = true
            splitView.setPosition(total * targetRatio, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
            isApplying = false
        }

        public func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !isApplying else { return }
            guard let splitView = notification.object as? NSSplitView else { return }
            guard splitView.arrangedSubviews.count == 2 else { return }
            let total = measuredLength(of: splitView.bounds.size)
            guard total > 0 else { return }
            let nextRatio = (measuredLength(of: splitView.arrangedSubviews[0].frame.size) / total).clamped(to: 0.05 ... 0.95)
            targetRatio = nextRatio
            Task { @MainActor in
                self.onRatioChange(nextRatio)
            }
        }

        public func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt _: Int
        ) -> CGFloat {
            max(proposedMinimumPosition, minimumPaneSize)
        }

        public func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt _: Int
        ) -> CGFloat {
            let total = measuredLength(of: splitView.bounds.size)
            return min(proposedMaximumPosition, max(minimumPaneSize, total - minimumPaneSize))
        }

        private func measuredLength(of size: CGSize) -> CGFloat {
            direction == .horizontal ? size.width : size.height
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

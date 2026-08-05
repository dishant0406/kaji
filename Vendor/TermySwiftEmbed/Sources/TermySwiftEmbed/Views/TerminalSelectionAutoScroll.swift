import AppKit

struct TerminalSelectionAutoScrollMetrics: Equatable {
    var boundsHeight: CGFloat
    var paddingY: CGFloat
    var cellHeight: CGFloat
    var displayOffset: Int
    var historySize: Int
}

enum TerminalSelectionAutoScrollPolicy {
    static func deltaLines(pointY: CGFloat, metrics: TerminalSelectionAutoScrollMetrics) -> Int {
        guard metrics.boundsHeight > 0,
              metrics.cellHeight > 0,
              metrics.historySize > 0
        else {
            return 0
        }

        let edge = max(metrics.cellHeight * 2, 28)
        let topDistance = metrics.boundsHeight - metrics.paddingY - pointY
        let bottomDistance = pointY - metrics.paddingY
        if topDistance < edge, metrics.displayOffset < metrics.historySize {
            return speed(distance: edge - topDistance, cellHeight: metrics.cellHeight)
        }
        if bottomDistance < edge, metrics.displayOffset > 0 {
            return -speed(distance: edge - bottomDistance, cellHeight: metrics.cellHeight)
        }
        return 0
    }

    private static func speed(distance: CGFloat, cellHeight: CGFloat) -> Int {
        max(1, min(8, Int(ceil(distance / max(1, cellHeight)))))
    }
}

@MainActor
final class TerminalSelectionAutoScroller {
    private var task: Task<Void, Never>?
    private var point: CGPoint = .zero
    private var metrics = TerminalSelectionAutoScrollMetrics(
        boundsHeight: 0,
        paddingY: 0,
        cellHeight: 1,
        displayOffset: 0,
        historySize: 0
    )

    func update(
        point: CGPoint,
        metrics: TerminalSelectionAutoScrollMetrics,
        onTick: @escaping (Int, CGPoint) -> Void
    ) {
        self.point = point
        self.metrics = metrics
        guard Self.shouldRun(pointY: point.y, metrics: metrics) else {
            stop()
            return
        }
        guard task == nil else {
            return
        }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(45))
                guard let self else {
                    return
                }
                let delta = TerminalSelectionAutoScrollPolicy.deltaLines(
                    pointY: self.point.y,
                    metrics: self.metrics
                )
                guard delta != 0 else {
                    self.stop()
                    return
                }
                self.metrics.displayOffset = max(
                    0,
                    min(self.metrics.historySize, self.metrics.displayOffset + delta)
                )
                onTick(delta, self.point)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func shouldRun(pointY: CGFloat, metrics: TerminalSelectionAutoScrollMetrics) -> Bool {
        TerminalSelectionAutoScrollPolicy.deltaLines(pointY: pointY, metrics: metrics) != 0
    }
}

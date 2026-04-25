import CoreGraphics
import Foundation

struct MarkdownSyncPoint: Equatable {
    let anchorID: String
    let startLine: Int
    let endLine: Int
    let localProgress: CGFloat

    var clampedProgress: CGFloat {
        min(max(localProgress, 0), 1)
    }

    var representativeLine: Int {
        let span = max(0, endLine - startLine)
        if span == 0 {
            return startLine
        }
        return startLine + Int(round(clampedProgress * CGFloat(span)))
    }
}

@MainActor
final class MarkdownSyncCoordinator {
    enum Driver {
        case editor
        case preview
    }

    struct Output: Equatable {
        var requestPreviewScroll: MarkdownSyncPoint?
        var requestEditorScrollLine: Int?

        var isEmpty: Bool {
            requestPreviewScroll == nil && requestEditorScrollLine == nil
        }
    }

    private let now: () -> TimeInterval

    private var driver: Driver?
    private var driverSince: TimeInterval = 0

    private var lastIssuedPreviewPoint: MarkdownSyncPoint?
    private var lastIssuedPreviewTime: TimeInterval = 0

    private var lastIssuedEditorLine: Int?
    private var lastIssuedEditorTime: TimeInterval = 0

    private var lastPreviewPoint: MarkdownSyncPoint?
    private var lastEditorPoint: MarkdownSyncPoint?

    init(now: @escaping () -> TimeInterval = { CFAbsoluteTimeGetCurrent() }) {
        self.now = now
    }

    func editorDidScroll(snapshot: MarkdownEditorAnchorSyncSnapshot, anchors: [MarkdownSyncAnchor]) -> Output {
        guard let point = syncPoint(from: snapshot, anchors: anchors) else {
            return Output()
        }

        lastEditorPoint = point

        let timestamp = now()
        guard shouldAcceptUpdate(from: .editor, timestamp: timestamp) else {
            return Output()
        }

        driver = .editor
        driverSince = timestamp
        lastIssuedPreviewPoint = point
        lastIssuedPreviewTime = timestamp
        return Output(requestPreviewScroll: point)
    }

    func previewDidScroll(point: MarkdownSyncPoint, totalLineCount: Int) -> Output {
        lastPreviewPoint = point

        let timestamp = now()
        guard shouldAcceptUpdate(from: .preview, timestamp: timestamp, incomingPreviewPoint: point) else {
            return Output()
        }

        driver = .preview
        driverSince = timestamp

        let lineIndex: Int
        let remainingLines = max(0, totalLineCount - point.endLine)
        if point.localProgress >= 0.985, remainingLines <= 6 {
            lineIndex = max(0, totalLineCount - 1)
        } else {
            lineIndex = max(0, min(totalLineCount - 1, point.representativeLine - 1))
        }
        lastIssuedEditorLine = lineIndex
        lastIssuedEditorTime = timestamp
        return Output(requestEditorScrollLine: lineIndex)
    }

    func previewDidRelayout() -> Output {
        guard driver == .editor,
              let lastIssuedPreviewPoint
        else {
            return Output()
        }

        let timestamp = now()
        let relayoutDelay: TimeInterval = 0.05
        let relayoutWindow: TimeInterval = 1.0
        let elapsed = timestamp - lastIssuedPreviewTime
        guard elapsed >= relayoutDelay, elapsed <= relayoutWindow else {
            return Output()
        }

        return Output(requestPreviewScroll: lastIssuedPreviewPoint)
    }

    private func shouldAcceptUpdate(
        from incoming: Driver,
        timestamp: TimeInterval,
        incomingPreviewPoint: MarkdownSyncPoint? = nil
    ) -> Bool {
        guard let driver else {
            return true
        }

        if driver == incoming {
            return true
        }

        let suppressionWindow: TimeInterval = 0.25
        if timestamp - driverSince < suppressionWindow {
            if incoming == .preview, let incomingPreviewPoint, let lastIssuedPreviewPoint {
                if isEquivalent(incomingPreviewPoint, lastIssuedPreviewPoint) {
                    return false
                }
            }

            if incoming == .editor, let lastIssuedEditorLine, let lastPreviewPoint {
                let line = lastPreviewPoint.representativeLine - 1
                if abs(line - lastIssuedEditorLine) <= 1 {
                    return false
                }
            }
        }

        return true
    }

    private func isEquivalent(_ lhs: MarkdownSyncPoint, _ rhs: MarkdownSyncPoint) -> Bool {
        if lhs.anchorID != rhs.anchorID {
            return false
        }
        if lhs.startLine != rhs.startLine || lhs.endLine != rhs.endLine {
            return false
        }
        return abs(lhs.clampedProgress - rhs.clampedProgress) <= 0.02
    }

    private func syncPoint(from snapshot: MarkdownEditorAnchorSyncSnapshot, anchors: [MarkdownSyncAnchor]) -> MarkdownSyncPoint? {
        guard let anchorID = snapshot.activeAnchorID else {
            return nil
        }

        guard let anchor = anchors.first(where: { $0.id == anchorID }) else {
            return nil
        }

        return MarkdownSyncPoint(
            anchorID: anchor.id,
            startLine: anchor.startLine,
            endLine: anchor.endLine,
            localProgress: CGFloat(snapshot.localProgress)
        )
    }
}

import CoreGraphics
import Foundation

@MainActor
final class MarkdownSyncCoordinator {
    enum Driver {
        case editor
        case preview
    }

    struct Output: Equatable {
        var requestPreviewScrollTop: CGFloat?
        var requestEditorScrollY: CGFloat?

        var isEmpty: Bool {
            requestPreviewScrollTop == nil && requestEditorScrollY == nil
        }
    }

    private let now: () -> TimeInterval

    private var driver: Driver?
    private var driverSince: TimeInterval = 0

    private var lastIssuedPreviewScrollTop: CGFloat?
    private var lastIssuedEditorScrollY: CGFloat?
    private var lastEditorInputScrollY: CGFloat?
    private var lastPreviewInputScrollTop: CGFloat?
    private var lastEditorInputTime: TimeInterval?
    private var lastPreviewInputTime: TimeInterval?
    private let echoTolerance: CGFloat = 2
    private let duplicateTolerance: CGFloat = 0.5
    private let suppressionWindow: TimeInterval = 0.32
    private let activeInputWindow: TimeInterval = 0.42

    init(now: @escaping () -> TimeInterval = { CFAbsoluteTimeGetCurrent() }) {
        self.now = now
    }

    func editorDidScroll(scrollY: CGFloat, map: MarkdownSyncMap) -> Output {
        guard !map.isEmpty else { return Output() }

        let timestamp = now()
        lastEditorInputScrollY = scrollY
        lastEditorInputTime = timestamp
        guard shouldAcceptUpdate(from: .editor, timestamp: timestamp, incoming: scrollY) else {
            return Output()
        }

        let target = map.previewScrollTop(forEditorScrollY: scrollY)
        if let lastIssuedPreviewScrollTop, abs(target - lastIssuedPreviewScrollTop) < duplicateTolerance {
            return Output()
        }

        driver = .editor
        driverSince = timestamp
        lastIssuedPreviewScrollTop = target
        return Output(requestPreviewScrollTop: target)
    }

    func previewDidScroll(scrollTop: CGFloat, map: MarkdownSyncMap) -> Output {
        guard !map.isEmpty else { return Output() }

        let timestamp = now()
        lastPreviewInputScrollTop = scrollTop
        lastPreviewInputTime = timestamp
        guard shouldAcceptUpdate(from: .preview, timestamp: timestamp, incoming: scrollTop) else {
            return Output()
        }

        let target = map.editorScrollY(forPreviewScrollTop: scrollTop)
        if let lastIssuedEditorScrollY, abs(target - lastIssuedEditorScrollY) < duplicateTolerance {
            return Output()
        }

        driver = .preview
        driverSince = timestamp
        lastIssuedEditorScrollY = target
        return Output(requestEditorScrollY: target)
    }

    func reissueAfterRelayout(map: MarkdownSyncMap) -> Output {
        guard !map.isEmpty else { return Output() }
        guard let driver else { return Output() }

        switch driver {
        case .editor:
            guard shouldReissue(for: .editor, timestamp: now()) else { return Output() }
            guard let lastEditorInputScrollY else { return Output() }
            let target = map.previewScrollTop(forEditorScrollY: lastEditorInputScrollY)
            lastIssuedPreviewScrollTop = target
            return Output(requestPreviewScrollTop: target)
        case .preview:
            guard shouldReissue(for: .preview, timestamp: now()) else { return Output() }
            guard let lastPreviewInputScrollTop else { return Output() }
            let target = map.editorScrollY(forPreviewScrollTop: lastPreviewInputScrollTop)
            lastIssuedEditorScrollY = target
            return Output(requestEditorScrollY: target)
        }
    }

    private func shouldAcceptUpdate(from incoming: Driver, timestamp: TimeInterval, incoming value: CGFloat) -> Bool {
        guard let driver else { return true }
        if driver == incoming {
            return true
        }

        if isEcho(from: incoming, value: value) {
            return false
        }

        guard timestamp - driverSince < suppressionWindow else { return true }

        switch incoming {
        case .editor:
            guard let lastIssuedEditorScrollY else { return true }
            return abs(value - lastIssuedEditorScrollY) > echoTolerance
        case .preview:
            guard let lastIssuedPreviewScrollTop else { return true }
            return abs(value - lastIssuedPreviewScrollTop) > echoTolerance
        }
    }

    private func shouldReissue(for reissueDriver: Driver, timestamp: TimeInterval) -> Bool {
        switch reissueDriver {
        case .editor:
            guard let lastPreviewInputTime else { return true }
            return timestamp - lastPreviewInputTime > activeInputWindow
        case .preview:
            guard let lastEditorInputTime else { return true }
            return timestamp - lastEditorInputTime > activeInputWindow
        }
    }

    private func isEcho(from incoming: Driver, value: CGFloat) -> Bool {
        switch incoming {
        case .editor:
            guard let lastIssuedEditorScrollY else { return false }
            return abs(value - lastIssuedEditorScrollY) <= echoTolerance
        case .preview:
            guard let lastIssuedPreviewScrollTop else { return false }
            return abs(value - lastIssuedPreviewScrollTop) <= echoTolerance
        }
    }
}

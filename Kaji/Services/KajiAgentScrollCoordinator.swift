import AppKit
import Foundation

@MainActor
@Observable
final class KajiAgentScrollCoordinator {
    private weak var scrollView: NSScrollView?
    private var observer: NSObjectProtocol?
    private var pendingBottomScroll: Task<Void, Never>?
    private var pendingTurnScroll: Task<Void, Never>?
    private var lastProgrammaticScrollAt = Date.distantPast
    private var programmaticScrollSuppression: TimeInterval = 0.18
    private var lastObservedOriginY: CGFloat?
    var isLocked = false
    var hasUnseenTail = false
    private var pendingTurnID: UUID?

    func attach(_ scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else { return }
        detach()
        self.scrollView = scrollView
        lastObservedOriginY = scrollView.documentVisibleRect.origin.y
        scrollView.verticalScrollElasticity = .allowed
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            Task { @MainActor in
                guard let self, let scrollView else { return }
                self.observe(scrollView)
            }
        }
    }

    func detach() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        pendingBottomScroll?.cancel()
        pendingBottomScroll = nil
        pendingTurnScroll?.cancel()
        pendingTurnScroll = nil
        scrollView = nil
        lastObservedOriginY = nil
    }

    func handleTailChanged() {
        guard let scrollView else {
            hasUnseenTail = true
            return
        }
        if let state = KajiAgentScrollLockPolicy.tailChangedState(
            distanceFromBottom: distanceFromBottom(scrollView),
            current: scrollState
        ) {
            apply(state)
            return
        }
        scheduleScrollToBottom(force: false, animated: false)
    }

    func scrollToBottom(force: Bool) {
        if force {
            isLocked = false
            hasUnseenTail = false
        }
        scheduleScrollToBottom(force: force, animated: force)
    }

    func scrollToTurn(_ id: UUID) {
        pendingTurnID = id
        if isLocked {
            hasUnseenTail = true
            return
        }
        scheduleScrollToTurn(force: false)
    }

    private func observe(_ scrollView: NSScrollView) {
        let originY = scrollView.documentVisibleRect.origin.y
        defer { lastObservedOriginY = originY }

        if let lastObservedOriginY, originY < lastObservedOriginY - 0.5 {
            apply(KajiAgentScrollLockPolicy.manualScrollState(current: scrollState))
            return
        }

        if Date().timeIntervalSince(lastProgrammaticScrollAt) < programmaticScrollSuppression { return }
        apply(KajiAgentScrollLockPolicy.observedState(distanceFromBottom: distanceFromBottom(scrollView), current: scrollState))
    }

    private func scheduleScrollToBottom(force: Bool, animated: Bool) {
        pendingBottomScroll?.cancel()
        pendingBottomScroll = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(force ? 0 : 16))
            guard !Task.isCancelled, let self, let scrollView = self.scrollView else { return }
            self.performScrollToBottom(scrollView, force: force, animated: animated)
        }
    }

    private func scheduleScrollToTurn(force: Bool) {
        pendingTurnScroll?.cancel()
        pendingTurnScroll = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(force ? 0 : 120))
            guard !Task.isCancelled, let self, let scrollView = self.scrollView, let id = self.pendingTurnID else { return }
            self.performScrollToTurn(id, scrollView: scrollView, force: force)
        }
    }

    private func performScrollToBottom(_ scrollView: NSScrollView, force: Bool, animated: Bool) {
        let distance = distanceFromBottom(scrollView)
        guard force || KajiAgentScrollLockPolicy.shouldPerformAutoScroll(distanceFromBottom: distance, current: scrollState) else {
            apply(KajiAgentScrollLockPolicy.manualScrollState(current: scrollState))
            hasUnseenTail = true
            return
        }

        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let visibleHeight = scrollView.documentVisibleRect.height
        let y = max(0, documentHeight - visibleHeight)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            }
        } else {
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        markProgrammaticScroll(targetOriginY: y, animated: animated)
        isLocked = false
        hasUnseenTail = false
    }

    private func performScrollToTurn(_ id: UUID, scrollView: NSScrollView, force: Bool) {
        if !force, isLocked {
            hasUnseenTail = true
            return
        }
        guard let document = scrollView.documentView,
              let target = findView(withIdentifier: id.uuidString, in: document)
        else {
            performScrollToBottom(scrollView, force: true, animated: false)
            return
        }
        let rect = target.convert(target.bounds, to: document)
        let y = max(0, rect.minY - 8)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        markProgrammaticScroll(targetOriginY: y, animated: false)
        if force {
            isLocked = false
            hasUnseenTail = false
        }
    }

    private func markProgrammaticScroll(targetOriginY: CGFloat, animated: Bool) {
        lastProgrammaticScrollAt = Date()
        programmaticScrollSuppression = animated ? 0.18 : 0.03
        lastObservedOriginY = targetOriginY
    }

    private func findView(withIdentifier identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        for subview in view.subviews {
            if let found = findView(withIdentifier: identifier, in: subview) { return found }
        }
        return nil
    }

    private var scrollState: KajiAgentScrollLockState {
        KajiAgentScrollLockState(isLocked: isLocked, hasUnseenTail: hasUnseenTail)
    }

    private func apply(_ state: KajiAgentScrollLockState) {
        isLocked = state.isLocked
        hasUnseenTail = state.hasUnseenTail
    }

    private func distanceFromBottom(_ scrollView: NSScrollView) -> CGFloat {
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        return max(0, documentHeight - scrollView.documentVisibleRect.maxY)
    }
}

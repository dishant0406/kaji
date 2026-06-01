import AppKit
import Foundation

@MainActor
@Observable
final class KajiAgentScrollCoordinator {
    private weak var scrollView: NSScrollView?
    private var observer: NSObjectProtocol?
    private var pendingScroll: Task<Void, Never>?
    private var lastProgrammaticScrollAt = Date.distantPast
    var isLocked = false
    var hasUnseenTail = false
    private var pendingTurnID: UUID?

    func attach(_ scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else { return }
        detach()
        self.scrollView = scrollView
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
        pendingScroll?.cancel()
        pendingScroll = nil
        scrollView = nil
    }

    func handleTailChanged() {
        guard !isLocked else {
            hasUnseenTail = true
            return
        }
        scheduleScrollToBottom(force: false)
    }

    func scrollToBottom(force: Bool) {
        if force {
            isLocked = false
            hasUnseenTail = false
        }
        scheduleScrollToBottom(force: force)
    }

    func scrollToTurn(_ id: UUID) {
        pendingTurnID = id
        scheduleScrollToTurn()
    }

    private func observe(_ scrollView: NSScrollView) {
        if Date().timeIntervalSince(lastProgrammaticScrollAt) < 0.18 { return }
        let distance = distanceFromBottom(scrollView)
        if distance < 72 {
            isLocked = false
            hasUnseenTail = false
        } else {
            isLocked = true
        }
    }

    private func scheduleScrollToBottom(force: Bool) {
        pendingScroll?.cancel()
        pendingScroll = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(force ? 0 : 90))
            guard !Task.isCancelled, let self, let scrollView = self.scrollView else { return }
            self.performScrollToBottom(scrollView)
        }
    }

    private func scheduleScrollToTurn() {
        pendingScroll?.cancel()
        pendingScroll = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, let scrollView = self.scrollView, let id = self.pendingTurnID else { return }
            self.performScrollToTurn(id, scrollView: scrollView)
        }
    }

    private func performScrollToBottom(_ scrollView: NSScrollView) {
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let visibleHeight = scrollView.documentVisibleRect.height
        let y = max(0, documentHeight - visibleHeight)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
        lastProgrammaticScrollAt = Date()
        isLocked = false
        hasUnseenTail = false
    }

    private func performScrollToTurn(_ id: UUID, scrollView: NSScrollView) {
        guard let document = scrollView.documentView,
              let target = findView(withIdentifier: id.uuidString, in: document)
        else {
            performScrollToBottom(scrollView)
            return
        }
        let rect = target.convert(target.bounds, to: document)
        let y = max(0, rect.minY - 8)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        lastProgrammaticScrollAt = Date()
        isLocked = false
        hasUnseenTail = false
    }

    private func findView(withIdentifier identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        for subview in view.subviews {
            if let found = findView(withIdentifier: identifier, in: subview) { return found }
        }
        return nil
    }

    private func distanceFromBottom(_ scrollView: NSScrollView) -> CGFloat {
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        return max(0, documentHeight - scrollView.documentVisibleRect.maxY)
    }
}

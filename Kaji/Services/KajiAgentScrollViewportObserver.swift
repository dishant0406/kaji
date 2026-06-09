import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class KajiAgentScrollViewportObserver {
    private weak var scrollView: NSScrollView?
    private var observer: NSObjectProtocol?
    var scrollOffset: CGFloat = 0
    var viewportHeight: CGFloat = 0

    func attach(_ scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else {
            refresh(scrollView)
            return
        }
        detach()
        self.scrollView = scrollView
        refresh(scrollView)
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            Task { @MainActor in
                guard let self, let scrollView else { return }
                self.refresh(scrollView)
            }
        }
    }

    func detach() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        scrollView = nil
        scrollOffset = 0
        viewportHeight = 0
    }

    func adjustOffset(by delta: CGFloat) {
        guard abs(delta) > 0.5, let scrollView else { return }
        let y = max(0, scrollView.documentVisibleRect.origin.y + delta)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refresh(scrollView)
    }

    private func refresh(_ scrollView: NSScrollView) {
        scrollOffset = max(0, scrollView.documentVisibleRect.origin.y)
        viewportHeight = max(0, scrollView.documentVisibleRect.height)
    }
}

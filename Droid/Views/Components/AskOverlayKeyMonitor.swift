import AppKit
import SwiftUI

struct AskOverlayKeyMonitor: NSViewRepresentable {
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void

    func makeNSView(context: Context) -> AskOverlayKeyMonitorView {
        let view = AskOverlayKeyMonitorView()
        view.onSubmit = onSubmit
        view.onEscape = onEscape
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        return view
    }

    func updateNSView(_ nsView: AskOverlayKeyMonitorView, context: Context) {
        nsView.onSubmit = onSubmit
        nsView.onEscape = onEscape
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
    }
}

final class AskOverlayKeyMonitorView: NSView {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeKeyMonitor()
        } else {
            installKeyMonitorIfNeeded()
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            guard !(window.firstResponder is NSTextView) else { return event }
            guard event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) else { return event }
            switch event.keyCode {
            case 36:
                self.onSubmit?()
                return nil
            case 53:
                self.onEscape?()
                return nil
            case 126:
                self.onArrowUp?()
                return nil
            case 125:
                self.onArrowDown?()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

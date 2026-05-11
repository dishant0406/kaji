import AppKit
import SwiftUI

struct AskOverlayKeyMonitor: NSViewRepresentable {
    let onSubmit: () -> Void
    var onShiftSubmit: (() -> Void)?
    var onSpace: (() -> Bool)?
    let onEscape: () -> Void
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    var onPaste: (() -> Bool)?

    func makeNSView(context: Context) -> AskOverlayKeyMonitorView {
        let view = AskOverlayKeyMonitorView()
        view.onSubmit = onSubmit
        view.onShiftSubmit = onShiftSubmit
        view.onSpace = onSpace
        view.onEscape = onEscape
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onPaste = onPaste
        return view
    }

    func updateNSView(_ nsView: AskOverlayKeyMonitorView, context: Context) {
        nsView.onSubmit = onSubmit
        nsView.onShiftSubmit = onShiftSubmit
        nsView.onSpace = onSpace
        nsView.onEscape = onEscape
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onPaste = onPaste
    }
}

final class AskOverlayKeyMonitorView: NSView {
    var onSubmit: (() -> Void)?
    var onShiftSubmit: (() -> Void)?
    var onSpace: (() -> Bool)?
    var onEscape: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onPaste: (() -> Bool)?
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
            if event.modifierFlags.contains(.command), event.keyCode == 9, self.onPaste?() == true {
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.isEmpty || flags == .shift else { return event }
            switch event.keyCode {
            case 36:
                if flags == .shift {
                    self.onShiftSubmit?()
                } else {
                    self.onSubmit?()
                }
                return nil
            case 49:
                return self.onSpace?() == true ? nil : event
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

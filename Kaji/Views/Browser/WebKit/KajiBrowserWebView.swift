import AppKit
import WebKit

@MainActor
final class KajiBrowserWebView: WKWebView {
    var allowsFocus = true
    var onBackMouse: (() -> Void)?
    var onForwardMouse: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        guard allowsFocus else { return false }
        return super.becomeFirstResponder()
    }

    override func otherMouseUp(with event: NSEvent) {
        switch event.buttonNumber {
        case 3:
            onBackMouse?()
        case 4:
            onForwardMouse?()
        default:
            super.otherMouseUp(with: event)
        }
    }
}

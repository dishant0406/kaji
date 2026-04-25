import AppKit
import WebKit

final class MarkdownPassiveWebView: WKWebView {
    var blocksUserScrollInput = false

    override func scrollWheel(with event: NSEvent) {
        if blocksUserScrollInput {
            return
        }
        super.scrollWheel(with: event)
    }
}

extension WKWebView {
    var safeScrollView: NSScrollView? {
        for subview in subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
        }
        return nil
    }
}

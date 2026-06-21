import AppKit
import WebKit

@MainActor
final class MonacoEditorHostView: NSView {
    private(set) weak var webView: WKWebView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        webView?.frame = bounds
    }

    func attach(_ nextWebView: WKWebView) {
        guard webView !== nextWebView else { return }
        webView?.removeFromSuperview()
        webView = nextWebView
        nextWebView.frame = bounds
        nextWebView.autoresizingMask = [.width, .height]
        addSubview(nextWebView)
    }

    func detach() {
        webView?.removeFromSuperview()
        webView = nil
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = KajiTheme.nsBg.cgColor
        layer?.isOpaque = true
    }
}

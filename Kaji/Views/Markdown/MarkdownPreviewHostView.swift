import AppKit
import WebKit

final class MarkdownPreviewHostView: NSView {
    weak var surface: MarkdownPreviewSurface?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = KajiTheme.nsBg.cgColor
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: 240)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        surface?.webView.frame = bounds
    }

    func attach(surface: MarkdownPreviewSurface, visible: Bool) {
        self.surface = surface
        if surface.webView.superview !== self {
            surface.webView.removeFromSuperview()
            addSubview(surface.webView)
        }
        surface.webView.frame = bounds
        surface.webView.isHidden = false
        surface.webView.alphaValue = visible ? 1 : 0
    }

    func hide() {
        guard let webView = surface?.webView else { return }
        webView.alphaValue = 0
    }

    func reveal() {
        guard let webView = surface?.webView, webView.alphaValue < 1 else { return }
        webView.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.05
            webView.animator().alphaValue = 1
        }
    }

    func clearReference(to surface: MarkdownPreviewSurface) {
        guard self.surface === surface else { return }
        self.surface = nil
    }

    func detachSurface() -> MarkdownPreviewSurface? {
        let detached = surface
        surface = nil
        detached?.webView.removeFromSuperview()
        return detached
    }
}

import AppKit
import WebKit

struct MarkdownPreviewCallbacks {
    let onMetrics: (MarkdownPreviewMetrics) -> Void
    let onScroll: (CGFloat) -> Void
    let onReady: () -> Void
}

@MainActor
final class MarkdownPreviewSurface: MarkdownPreviewReusableSurface {
    let webView: WKWebView
    var ownerID: String?
    var lastUsed = Date()
    private(set) var disposed = false
    private let coordinator: MarkdownPreviewWebCoordinator
    private weak var hostView: MarkdownPreviewHostView?
    private var hasRenderedContent = false

    init() {
        let controller = WKUserContentController()
        let schemeHandler = MarkdownPreviewURLSchemeHandler()
        let configuration = MarkdownPreviewWebConfiguration.make(
            userContentController: controller,
            schemeHandler: schemeHandler
        )
        coordinator = MarkdownPreviewWebCoordinator(
            userContentController: controller,
            schemeHandler: schemeHandler
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        configureWebView()
        coordinator.bind(webView: webView)
        coordinator.onReady = { [weak self] in self?.contentDidRender() }
        webView.load(URLRequest(url: MarkdownPreviewAssetStore.shellURL))
    }

    func prepareForReuse(ownerID: String) {
        self.ownerID = ownerID
        hasRenderedContent = false
        coordinator.resetForReuse()
        hostView?.hide()
    }

    func attach(to hostView: MarkdownPreviewHostView) {
        if self.hostView !== hostView {
            self.hostView?.clearReference(to: self)
        }
        self.hostView = hostView
        hostView.attach(surface: self, visible: hasRenderedContent)
    }

    func update(
        payload: MarkdownPreviewPayload,
        scrollRequestVersion: Int,
        scrollRequest: CGFloat?,
        callbacks: MarkdownPreviewCallbacks
    ) {
        coordinator.onMetrics = callbacks.onMetrics
        coordinator.onScroll = callbacks.onScroll
        coordinator.onReady = { [weak self] in
            self?.contentDidRender()
            callbacks.onReady()
        }
        coordinator.update(
            payload: payload,
            scrollRequestVersion: scrollRequestVersion,
            scrollRequest: scrollRequest
        )
    }

    func detach(from hostView: MarkdownPreviewHostView) {
        guard self.hostView === hostView else { return }
        self.hostView = nil
        coordinator.onMetrics = { _ in }
        coordinator.onScroll = { _ in }
        coordinator.onReady = {}
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        coordinator.dispose()
        webView.removeFromSuperview()
        hostView = nil
    }

    private func configureWebView() {
        webView.underPageBackgroundColor = KajiTheme.nsBg
        webView.wantsLayer = true
        webView.layer?.backgroundColor = KajiTheme.nsBg.cgColor
        if #available(macOS 13.3, *) {
            webView.isInspectable = false
        }
    }

    private func contentDidRender() {
        hasRenderedContent = true
        hostView?.reveal()
    }
}

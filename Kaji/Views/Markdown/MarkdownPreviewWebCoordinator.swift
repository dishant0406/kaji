import AppKit
import WebKit

final class MarkdownPreviewWebCoordinator: NSObject, WKNavigationDelegate, MarkdownPreviewMessageTarget {
    static let messageNames = ["markdownShellReady", "markdownReady", "markdownMetrics", "markdownScroll"]

    let schemeHandler: MarkdownPreviewURLSchemeHandler
    private let userContentController: WKUserContentController
    private var proxies: [MarkdownPreviewMessageProxy] = []
    private weak var webView: WKWebView?
    private var ready = false
    private var lastPayload: MarkdownPreviewPayload?
    private var pendingPayload: MarkdownPreviewPayload?
    private var lastScrollRequestVersion = 0
    var onReady: () -> Void = {}
    var onMetrics: (MarkdownPreviewMetrics) -> Void = { _ in }
    var onScroll: (CGFloat) -> Void = { _ in }

    init(userContentController: WKUserContentController, schemeHandler: MarkdownPreviewURLSchemeHandler) {
        self.userContentController = userContentController
        self.schemeHandler = schemeHandler
        super.init()
        installHandlers()
    }

    func bind(webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
    }

    func resetForReuse() {
        lastPayload = nil
        pendingPayload = nil
        lastScrollRequestVersion = 0
    }

    func update(payload: MarkdownPreviewPayload, scrollRequestVersion: Int, scrollRequest: CGFloat?) {
        schemeHandler.allowedRoot = payload.baseURL.flatMap(URL.init(string:))?.standardizedFileURL
        if payload != lastPayload {
            lastPayload = payload
            render(payload)
        }
        guard scrollRequestVersion != lastScrollRequestVersion else { return }
        lastScrollRequestVersion = scrollRequestVersion
        guard let scrollRequest else { return }
        evaluate("window.KajiMarkdownPreview&&window.KajiMarkdownPreview.scrollTo(\(scrollRequest));")
    }

    func receiveMarkdownPreviewMessage(_ message: WKScriptMessage) {
        switch message.name {
        case "markdownShellReady":
            ready = true
            pendingPayload.map(render)
            pendingPayload = nil
        case "markdownReady":
            onReady()
        case "markdownMetrics":
            decode(message.body, as: MarkdownPreviewMetrics.self).map(onMetrics)
        case "markdownScroll":
            if let value = (message.body as? [String: Any])?["scrollTop"] as? Double {
                onScroll(CGFloat(value))
            }
        default:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard action.targetFrame?.isMainFrame == true,
              let url = action.request.url,
              url.scheme?.hasPrefix("http") == true
        else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func dispose() {
        Self.messageNames.forEach(userContentController.removeScriptMessageHandler(forName:))
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        proxies.removeAll()
        onReady = {}
        onMetrics = { _ in }
        onScroll = { _ in }
    }

    private func installHandlers() {
        proxies = Self.messageNames.map { name in
            let proxy = MarkdownPreviewMessageProxy(target: self)
            userContentController.add(proxy, name: name)
            return proxy
        }
    }

    private func render(_ payload: MarkdownPreviewPayload) {
        guard ready else {
            pendingPayload = payload
            return
        }
        guard let json = MarkdownPreviewAssetStore.javaScriptLiteral(payload) else { return }
        evaluate("window.KajiMarkdownPreview.render(\(json));")
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private func decode<T: Decodable>(_ value: Any, as type: T.Type) -> T? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

import AppKit
import WebKit

final class MarkdownPreviewWebCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let schemeHandler = MarkdownPreviewSchemeHandler(resourceRoot: MarkdownPreviewResourceLoader.resourceRoot)
    weak var webView: WKWebView?
    private let onMetrics: (MarkdownPreviewMetrics) -> Void
    private let onScroll: (CGFloat) -> Void
    private var ready = false
    private var pendingPayload: MarkdownPreviewPayload?
    private var lastPayload: MarkdownPreviewPayload?
    private var lastScrollRequestVersion = 0

    init(onMetrics: @escaping (MarkdownPreviewMetrics) -> Void, onScroll: @escaping (CGFloat) -> Void) {
        self.onMetrics = onMetrics
        self.onScroll = onScroll
    }

    func installHandlers(on controller: WKUserContentController) {
        for item in ["markdownShellReady", "markdownReady", "markdownMetrics", "markdownScroll"] {
            controller.add(self, name: item)
        }
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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "markdownShellReady":
            ready = true
            if let pendingPayload {
                self.pendingPayload = nil
                render(pendingPayload)
            }
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
        guard action.targetFrame?.isMainFrame == true, let url = action.request.url, url.scheme?.hasPrefix("http") == true else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    private func render(_ payload: MarkdownPreviewPayload) {
        guard ready else {
            pendingPayload = payload
            return
        }
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
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

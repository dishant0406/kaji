import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewMetrics: Codable, Equatable {
    let geometries: [MarkdownPreviewAnchorGeometry]
    let maxScrollTop: CGFloat
    let viewportHeight: CGFloat
}

struct MarkdownPreviewWebView: NSViewRepresentable {
    let payload: MarkdownPreviewPayload
    let scrollRequestVersion: Int
    let scrollRequest: CGFloat?
    let onMetrics: (MarkdownPreviewMetrics) -> Void
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> MarkdownPreviewWebCoordinator {
        MarkdownPreviewWebCoordinator(onMetrics: onMetrics, onScroll: onScroll)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        context.coordinator.installHandlers(on: controller)
        configuration.userContentController = controller
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "kaji-preview-file")
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: "kaji-preview-asset")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = KajiTheme.nsBg
        webView.wantsLayer = true
        webView.layer?.backgroundColor = KajiTheme.nsBg.cgColor
        webView.loadHTMLString(MarkdownPreviewResourceLoader.shellHTML(), baseURL: nil)
        context.coordinator.webView = webView
        context.coordinator.update(payload: payload, scrollRequestVersion: scrollRequestVersion, scrollRequest: scrollRequest)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.update(payload: payload, scrollRequestVersion: scrollRequestVersion, scrollRequest: scrollRequest)
    }
}

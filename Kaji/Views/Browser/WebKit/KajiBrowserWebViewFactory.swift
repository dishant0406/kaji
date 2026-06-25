import AppKit
import WebKit

@MainActor
enum KajiBrowserWebViewFactory {
    static func make() -> KajiBrowserWebView {
        let configuration = WKWebViewConfiguration()
        configure(configuration)
        let webView = KajiBrowserWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        webView.underPageBackgroundColor = NSColor.windowBackgroundColor
        return webView
    }

    private static func configure(_ configuration: WKWebViewConfiguration) {
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(pageEventScript())
    }

    private static func pageEventScript() -> WKUserScript {
        WKUserScript(
            source: KajiBrowserPageScripts.eventBridge,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }
}

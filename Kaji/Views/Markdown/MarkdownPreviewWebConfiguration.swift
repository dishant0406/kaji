import WebKit

@MainActor
enum MarkdownPreviewWebConfiguration {
    private static let processPool = WKProcessPool()

    static func make(
        userContentController: WKUserContentController,
        schemeHandler: MarkdownPreviewURLSchemeHandler
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = processPool
        configuration.userContentController = userContentController
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: MarkdownPreviewAssetStore.contentScheme)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: MarkdownPreviewAssetStore.fileScheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsAirPlayForMediaPlayback = false
        return configuration
    }
}

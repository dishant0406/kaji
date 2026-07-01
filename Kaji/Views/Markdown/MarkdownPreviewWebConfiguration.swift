import WebKit

@MainActor
enum MarkdownPreviewWebConfiguration {
    static func make(
        userContentController: WKUserContentController,
        schemeHandler: MarkdownPreviewURLSchemeHandler
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: MarkdownPreviewAssetStore.contentScheme)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: MarkdownPreviewAssetStore.fileScheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsAirPlayForMediaPlayback = false
        return configuration
    }
}

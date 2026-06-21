import AppKit
import WebKit

@MainActor
struct MonacoWebViewHost {
    let webView: WKWebView
    let userContentController: WKUserContentController
}

@MainActor
enum MonacoWebViewFactory {
    private static let dataStore = WKWebsiteDataStore.nonPersistent()

    static func makeHost() -> MonacoWebViewHost {
        let controller = WKUserContentController()
        controller.addUserScript(pageBackgroundScript())
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsAirPlayForMediaPlayback = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        configure(webView)
        return MonacoWebViewHost(webView: webView, userContentController: controller)
    }

    private static func configure(_ webView: WKWebView) {
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = KajiTheme.nsBg
        webView.wantsLayer = true
        webView.alphaValue = 0
        webView.layer?.backgroundColor = KajiTheme.nsBg.cgColor
        webView.layer?.isOpaque = false
        if #available(macOS 13.3, *) {
            webView.isInspectable = false
        }
    }

    private static func pageBackgroundScript() -> WKUserScript {
        WKUserScript(
            source: """
            document.documentElement.style.background = 'transparent';
            document.documentElement.style.margin = '0';
            document.addEventListener('DOMContentLoaded', function() {
              document.body.style.background = 'transparent';
              document.body.style.margin = '0';
              var editor = document.getElementById('editor');
              if (editor) editor.style.background = 'transparent';
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }
}

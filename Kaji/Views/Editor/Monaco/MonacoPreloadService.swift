import Foundation
import WebKit

@MainActor
final class MonacoPreloadService: NSObject, WKNavigationDelegate, MonacoMessageTarget {
    static let shared = MonacoPreloadService()

    private var host: MonacoWebViewHost?
    private var proxy: MonacoMessageProxy?
    private var isLoading = false
    private var isReady = false
    private var allowedHost: String?
    private var allowedPort: Int?

    func start() {
        guard host == nil, !isLoading else { return }
        guard let url = MonacoAssetServer.shared.ensureStarted() else { return }

        let nextHost = MonacoWebViewFactory.makeHost()
        let nextProxy = MonacoMessageProxy(target: self)
        nextHost.userContentController.add(nextProxy, name: "kajiMonaco")
        nextHost.webView.navigationDelegate = self

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "editorID", value: "preload")]
        guard let editorURL = components?.url else { return }

        host = nextHost
        proxy = nextProxy
        isLoading = true
        isReady = false
        allowedHost = editorURL.host
        allowedPort = editorURL.port
        nextHost.webView.load(URLRequest(url: editorURL))
        DebugFileLog.log("MonacoPreload", "started")
    }

    func takeReadyHost() -> MonacoWebViewHost? {
        guard isReady, let host else {
            start()
            return nil
        }

        host.userContentController.removeScriptMessageHandler(forName: "kajiMonaco")
        host.webView.navigationDelegate = nil
        self.host = nil
        proxy = nil
        isLoading = false
        isReady = false
        allowedHost = nil
        allowedPort = nil
        Task { @MainActor in
            self.start()
        }
        DebugFileLog.log("MonacoPreload", "prepared host consumed")
        return host
    }

    func receiveMonacoMessage(_ message: WKScriptMessage) {
        guard let bridgeMessage = decode(message.body) else { return }
        switch bridgeMessage.type {
        case .ready:
            isReady = true
            isLoading = false
            DebugFileLog.log("MonacoPreload", "ready")
        case .error:
            DebugFileLog.log("MonacoPreload", "error \(bridgeMessage.payload?.message ?? "unknown")")
        default:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        guard url.host == allowedHost, url.port == allowedPort else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func decode(_ body: Any) -> MonacoBridgeMessage? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }
        return try? JSONDecoder().decode(MonacoBridgeMessage.self, from: data)
    }
}

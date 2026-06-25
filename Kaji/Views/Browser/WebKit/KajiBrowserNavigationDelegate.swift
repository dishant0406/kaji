import AppKit
import WebKit

@MainActor
final class KajiBrowserNavigationDelegate: NSObject, WKNavigationDelegate {
    var started: ((WKWebView) -> Void)?
    var finished: ((WKWebView) -> Void)?
    var failed: ((WKWebView, Error) -> Void)?
    var terminated: ((WKWebView) -> Void)?
    var popupRequested: ((URL) -> Void)?
    var downloadDelegate: WKDownloadDelegate?
    var lastAttemptedURL: URL?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        started?(webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        started?(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed?(webView, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled else { return }
        guard nsError.domain != "WebKitErrorDomain" || nsError.code != 102 else { return }
        failed?(webView, error)
        KajiBrowserErrorPage.load(
            in: webView,
            failedURL: lastAttemptedURL?.absoluteString ?? webView.url?.absoluteString ?? "",
            error: nsError
        )
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        terminated?(webView)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, shouldOpenExternally(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            popupRequested?(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame != false {
            lastAttemptedURL = navigationAction.request.url
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame else {
            decisionHandler(.allow)
            return
        }
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = downloadDelegate
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloadDelegate
    }

    private func shouldOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return !["http", "https", "about", "file", "data", "blob"].contains(scheme)
    }
}

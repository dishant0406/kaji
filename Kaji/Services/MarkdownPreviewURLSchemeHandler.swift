import Foundation
import WebKit

final class MarkdownPreviewURLSchemeHandler: NSObject, WKURLSchemeHandler {
    var allowedRoot: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let payload = response(for: url)
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(payload.response)
        urlSchemeTask.didReceive(payload.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func response(for url: URL) -> MarkdownPreviewAssetResponse? {
        if url.scheme == MarkdownPreviewAssetStore.contentScheme {
            return MarkdownPreviewAssetStore.bundledResponse(for: url)
        }
        if url.scheme == MarkdownPreviewAssetStore.fileScheme {
            return MarkdownPreviewAssetStore.localFileResponse(for: url, allowedRoot: allowedRoot)
        }
        return nil
    }
}

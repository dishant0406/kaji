import Foundation
import WebKit

@MainActor
enum KajiBrowserErrorPage {
    static func load(in webView: WKWebView, failedURL: String, error: NSError) {
        let title = title(for: error)
        let message = error.localizedDescription
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><style>
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;min-height:100vh;display:flex}
        body{align-items:center;justify-content:center;background:#171717;color:#eee}
        main{max-width:520px;padding:28px;text-align:center}h1{font-size:19px}p{color:#aaa;line-height:1.45}
        .url{font-size:12px;color:#777;word-break:break-all}
        button{margin-top:18px;padding:7px 18px;border-radius:8px;border:1px solid #555;background:#2b2b2b;color:#eee}
        </style></head><body><main><h1>\(escape(title))</h1><p>\(escape(message))</p>
        <div class="url">\(escape(failedURL))</div><button onclick="location.reload()">Reload</button></main></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: failedURL))
    }

    private static func title(for error: NSError) -> String {
        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorCannotConnectToHost),
             (NSURLErrorDomain, NSURLErrorCannotFindHost),
             (NSURLErrorDomain, NSURLErrorTimedOut):
            "Can’t reach this page"
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet):
            "No internet connection"
        case (NSURLErrorDomain, NSURLErrorSecureConnectionFailed),
             (NSURLErrorDomain, NSURLErrorServerCertificateUntrusted):
            "Connection isn’t secure"
        default:
            "Can’t open this page"
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

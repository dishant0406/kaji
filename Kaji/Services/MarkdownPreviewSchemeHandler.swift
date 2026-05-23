import Foundation
import UniformTypeIdentifiers
import WebKit

final class MarkdownPreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    var allowedRoot: URL?
    let resourceRoot: URL?

    init(resourceRoot: URL?) {
        self.resourceRoot = resourceRoot
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let fileURL = fileURL(for: url),
              isAllowed(fileURL, for: url.scheme),
              let data = try? Data(contentsOf: fileURL)
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: mimeType(for: fileURL),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fileURL(for url: URL) -> URL? {
        if url.scheme == "kaji-preview-asset" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let resourceRoot else { return nil }
            let direct = resourceRoot.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            return resourceRoot.appendingPathComponent("fonts").appendingPathComponent(path)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "path" })?.value
        else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    private func isAllowed(_ fileURL: URL, for scheme: String?) -> Bool {
        if scheme == "kaji-preview-asset" {
            return isDescendant(fileURL, of: resourceRoot)
        }
        return isDescendant(fileURL, of: allowedRoot)
    }

    private func isDescendant(_ fileURL: URL, of root: URL?) -> Bool {
        guard let root else { return false }
        let path = fileURL.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func mimeType(for url: URL) -> String {
        if url.pathExtension == "woff2" { return "font/woff2" }
        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

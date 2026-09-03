import Foundation
import UniformTypeIdentifiers

enum MarkdownPreviewAssetStore {
    static let contentScheme = "kaji-markdown"
    static let fileScheme = "kaji-markdown-file"
    static var shellURL: URL {
        URL(string: "\(contentScheme)://shell/index.html") ?? URL(fileURLWithPath: "/")
    }

    static var resourceRoot: URL? {
        if let directory = Bundle.appResources.url(forResource: "MarkdownPreview", withExtension: nil) {
            return directory
        }
        if let sourceDirectory = Bundle.appResources.resourceURL?.appendingPathComponent("MarkdownPreview", isDirectory: true),
           FileManager.default.fileExists(atPath: sourceDirectory.path)
        {
            return sourceDirectory
        }
        return Bundle.appResources.resourceURL
    }

    static func bundledResponse(for url: URL) -> MarkdownPreviewAssetResponse? {
        guard url.scheme == contentScheme else { return nil }
        if url.host == "shell" {
            return dataResponse(data: shellHTMLData, url: url, mimeType: "text/html")
        }
        guard url.host == "asset",
              let fileURL = bundledFileURL(path: normalizedPath(url.path)),
              let data = try? Data(contentsOf: fileURL)
        else { return nil }
        return dataResponse(data: data, url: url, mimeType: mimeType(for: fileURL))
    }

    static func localFileResponse(for url: URL, allowedRoot: URL?) -> MarkdownPreviewAssetResponse? {
        guard url.scheme == fileScheme,
              let fileURL = localFileURL(for: url),
              isDescendant(fileURL, of: allowedRoot),
              let data = try? Data(contentsOf: fileURL)
        else { return nil }
        return dataResponse(data: data, url: url, mimeType: mimeType(for: fileURL))
    }

    static func javaScriptLiteral(_ value: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    static func fileURLString(_ url: URL) -> String {
        var components = URLComponents()
        components.scheme = fileScheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: url.standardizedFileURL.path)]
        return components.url?.absoluteString ?? ""
    }

    private static var shellHTMLData: Data {
        if let url = bundledFileURL(path: "preview.html"),
           let data = try? Data(contentsOf: url)
        {
            return data
        }
        return fallbackHTML.data(using: .utf8) ?? Data()
    }

    private static var fallbackHTML: String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"></head><body><main id="content"></main></body></html>
        """
    }

    private static func bundledFileURL(path: String) -> URL? {
        bundledFileURL(path: path, resourceRoot: resourceRoot)
    }

    static func bundledFileURL(path: String, resourceRoot: URL?) -> URL? {
        let normalized = normalizedPath(path)
        guard !normalized.isEmpty, let resourceRoot else { return nil }
        return bundledFileCandidates(path: normalized, resourceRoot: resourceRoot)
            .first { fileURL in
                isDescendant(fileURL, of: resourceRoot)
                    && FileManager.default.fileExists(atPath: fileURL.path)
            }
    }

    private static func localFileURL(for url: URL) -> URL? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "path" }?
            .value
            .map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath() }
    }

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func bundledFileCandidates(path: String, resourceRoot: URL) -> [URL] {
        let nested = resourceRoot.appendingPathComponent(path).standardizedFileURL
        let flattened = resourceRoot
            .appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
            .standardizedFileURL
        return nested == flattened ? [nested] : [nested, flattened]
    }

    private static func dataResponse(data: Data, url: URL, mimeType: String) -> MarkdownPreviewAssetResponse {
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        return MarkdownPreviewAssetResponse(data: data, response: response)
    }

    private static func isDescendant(_ fileURL: URL, of root: URL?) -> Bool {
        guard let root else { return false }
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func mimeType(for url: URL) -> String {
        if url.pathExtension == "woff2" {
            return "font/woff2"
        }
        return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

struct MarkdownPreviewAssetResponse {
    let data: Data
    let response: URLResponse
}

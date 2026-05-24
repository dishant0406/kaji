import Foundation

struct MarkdownPreviewLinkRequest: Codable, Hashable {
    let href: String
    let resolvedURL: String?
}

enum MarkdownPreviewLinkAction: Equatable {
    case anchor(String)
    case localFile(URL)
    case external(URL)
    case missingLocalFile(URL)
    case blockedLocalFile(URL)
    case unsupported(URL)
    case ignored
}

enum MarkdownPreviewLinkResolver {
    static func resolve(
        _ request: MarkdownPreviewLinkRequest,
        documentURL: URL?,
        allowedRoot: URL?,
        fileManager: FileManager = .default
    ) -> MarkdownPreviewLinkAction {
        let href = request.href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return .ignored }
        if href.hasPrefix("#") { return .anchor(String(href.dropFirst())) }
        guard let url = resolvedURL(for: request, documentURL: documentURL) else { return .ignored }
        guard let scheme = url.scheme?.lowercased() else { return .unsupported(url) }
        if scheme == "file" {
            return localFileAction(url, allowedRoot: allowedRoot, fileManager: fileManager)
        }
        if ["http", "https", "mailto"].contains(scheme) {
            return .external(url)
        }
        return .unsupported(url)
    }

    private static func resolvedURL(for request: MarkdownPreviewLinkRequest, documentURL: URL?) -> URL? {
        if let resolved = request.resolvedURL, let url = URL(string: resolved) {
            return url
        }
        guard let documentURL else { return URL(string: request.href) }
        return URL(string: request.href, relativeTo: documentURL.deletingLastPathComponent())?.absoluteURL
    }

    private static func localFileAction(
        _ url: URL,
        allowedRoot: URL?,
        fileManager: FileManager
    ) -> MarkdownPreviewLinkAction {
        let fileURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard isDescendant(fileURL, of: allowedRoot) else { return .blockedLocalFile(fileURL) }
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missingLocalFile(fileURL) }
        return .localFile(fileURL)
    }

    private static func isDescendant(_ fileURL: URL, of root: URL?) -> Bool {
        guard let root else { return false }
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

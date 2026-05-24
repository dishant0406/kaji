import AppKit
import SwiftUI

struct MarkdownDocumentPreviewView: View {
    let content: String
    let filePath: String?
    let allowedRootPath: String?
    let onOpenLocalFile: ((URL) -> Void)?
    @Environment(AppTypographySettings.self) private var typography

    init(
        content: String,
        filePath: String?,
        allowedRootPath: String? = nil,
        onOpenLocalFile: ((URL) -> Void)? = nil
    ) {
        self.content = content
        self.filePath = filePath
        self.allowedRootPath = allowedRootPath
        self.onOpenLocalFile = onOpenLocalFile
    }

    var body: some View {
        MarkdownPreviewRepresentable(
            identity: identity,
            payload: payload,
            scrollRequestVersion: 0,
            scrollRequest: nil,
            onMetrics: { _ in },
            onScroll: { _ in },
            onReady: {},
            onLink: handleLink
        )
        .background(KajiTheme.bg)
        .onAppear {
            MarkdownPreviewSurfaceRegistry.shared.prewarm()
        }
    }

    private var identity: String {
        filePath.flatMap { $0.isEmpty ? nil : $0 } ?? "markdown-document-preview"
    }

    private var payload: MarkdownPreviewPayload {
        MarkdownPreviewPayload(
            content: content,
            baseURL: baseURL,
            allowedRootURL: allowedRootURL,
            allowRemoteImages: MarkdownPreviewPreferences.allowRemoteImages,
            anchors: [],
            theme: MarkdownPreviewThemeFactory.theme(),
            typography: MarkdownPreviewThemeFactory.typography(typography)
        )
    }

    private var baseURL: String? {
        guard let filePath, !filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: filePath).deletingLastPathComponent().absoluteString
    }

    private var allowedRootURL: String? {
        if let allowedRootPath, !allowedRootPath.isEmpty {
            return URL(fileURLWithPath: allowedRootPath, isDirectory: true).absoluteString
        }
        guard let filePath, !filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: filePath).deletingLastPathComponent().absoluteString
    }

    private var documentURL: URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    private var allowedRoot: URL? {
        if let allowedRootPath, !allowedRootPath.isEmpty {
            return URL(fileURLWithPath: allowedRootPath, isDirectory: true)
        }
        return documentURL?.deletingLastPathComponent()
    }

    private func handleLink(_ request: MarkdownPreviewLinkRequest) {
        let action = MarkdownPreviewLinkResolver.resolve(request, documentURL: documentURL, allowedRoot: allowedRoot)
        switch action {
        case .anchor,
             .ignored:
            return
        case let .localFile(url):
            if let onOpenLocalFile {
                onOpenLocalFile(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        case let .external(url):
            NSWorkspace.shared.open(url)
        case let .missingLocalFile(url):
            ToastState.shared.show("Markdown link target not found: \(url.lastPathComponent)")
        case .blockedLocalFile:
            ToastState.shared.show("Markdown link is outside the allowed folder")
        case let .unsupported(url):
            ToastState.shared.show("Unsupported markdown link: \(url.scheme ?? "unknown")")
        }
    }
}

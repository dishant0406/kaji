import SwiftUI

struct MarkdownDocumentPreviewView: View {
    let content: String
    let filePath: String?
    @Environment(AppTypographySettings.self) private var typography

    var body: some View {
        MarkdownPreviewRepresentable(
            identity: identity,
            payload: payload,
            scrollRequestVersion: 0,
            scrollRequest: nil,
            onMetrics: { _ in },
            onScroll: { _ in },
            onReady: {}
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
}

import SwiftUI

struct MarkdownDocumentPreviewView: View {
    let content: String
    let filePath: String?

    var body: some View {
        MarkdownPreviewWebView(
            payload: payload,
            scrollRequestVersion: 0,
            scrollRequest: nil,
            onMetrics: { _ in },
            onScroll: { _ in }
        )
        .background(KajiTheme.bg)
    }

    private var payload: MarkdownPreviewPayload {
        MarkdownPreviewPayload(
            content: content,
            baseURL: baseURL,
            allowRemoteImages: MarkdownPreviewPreferences.allowRemoteImages,
            anchors: [],
            theme: MarkdownPreviewThemeBuilder.current()
        )
    }

    private var baseURL: String? {
        guard let filePath, !filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: filePath).deletingLastPathComponent().absoluteString
    }
}

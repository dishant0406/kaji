import SwiftUI

struct AdvancedMarkdownPreviewView: View {
    @Bindable var state: EditorTabState
    let content: String

    var body: some View {
        MarkdownPreviewWebView(
            payload: payload,
            scrollRequestVersion: state.markdownPreviewScrollRequestVersion,
            scrollRequest: state.markdownPreviewScrollRequest,
            onMetrics: applyMetrics,
            onScroll: previewDidScroll
        )
        .background(KajiTheme.bg)
    }

    private var payload: MarkdownPreviewPayload {
        MarkdownPreviewPayload(
            content: content,
            baseURL: baseURL,
            allowRemoteImages: MarkdownPreviewPreferences.allowRemoteImages,
            anchors: state.markdownSyncAnchors(),
            theme: MarkdownPreviewThemeBuilder.current()
        )
    }

    private var baseURL: String? {
        guard !state.filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: state.filePath).deletingLastPathComponent().absoluteString
    }

    private func applyMetrics(_ metrics: MarkdownPreviewMetrics) {
        state.markdownPreviewGeometries = metrics.geometries
        state.markdownPreviewMaxScrollTop = metrics.maxScrollTop
        state.markdownPreviewViewportHeight = metrics.viewportHeight
        let output = state.markdownSyncCoordinator.reissueAfterRelayout(map: state.currentMarkdownSyncMap())
        state.applyMarkdownSyncOutput(output)
    }

    private func previewDidScroll(_ scrollTop: CGFloat) {
        guard state.markdownViewMode == .split, state.markdownScrollSyncEnabled else { return }
        if state.markdownScrollDriver != .preview {
            state.markdownScrollDriver = .preview
        }
        state.applyMarkdownSyncOutput(
            state.markdownSyncCoordinator.previewDidScroll(scrollTop: scrollTop, map: state.currentMarkdownSyncMap())
        )
    }
}

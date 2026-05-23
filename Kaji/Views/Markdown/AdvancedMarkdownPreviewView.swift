import SwiftUI

struct AdvancedMarkdownPreviewView: View {
    @Bindable var state: EditorTabState
    let content: String
    let presentationMode: EditorMarkdownViewMode
    @Environment(AppTypographySettings.self) private var typography

    var body: some View {
        MarkdownPreviewRepresentable(
            identity: previewIdentity,
            payload: payload,
            scrollRequestVersion: state.markdownPreviewScrollRequestVersion,
            scrollRequest: state.markdownPreviewScrollRequest,
            onMetrics: applyMetrics,
            onScroll: previewDidScroll,
            onReady: {}
        )
        .background(KajiTheme.bg)
        .onAppear {
            MarkdownPreviewSurfaceRegistry.shared.prewarm()
        }
    }

    private var previewIdentity: String {
        MarkdownPreviewIdentity.editor(tabID: state.id, mode: presentationMode)
    }

    private var payload: MarkdownPreviewPayload {
        MarkdownPreviewPayload(
            content: content,
            baseURL: baseURL,
            allowRemoteImages: MarkdownPreviewPreferences.allowRemoteImages,
            anchors: state.markdownSyncAnchors(),
            theme: MarkdownPreviewThemeFactory.theme(),
            typography: MarkdownPreviewThemeFactory.typography(typography)
        )
    }

    private var baseURL: String? {
        guard !state.filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: state.filePath).deletingLastPathComponent().absoluteString
    }

    private func applyMetrics(_ metrics: MarkdownPreviewMetrics) {
        guard state.markdownViewMode == presentationMode else { return }
        state.markdownPreviewGeometries = metrics.geometries
        state.markdownPreviewMaxScrollTop = metrics.maxScrollTop
        state.markdownPreviewViewportHeight = metrics.viewportHeight
        guard presentationMode == .split, state.markdownScrollSyncEnabled else { return }
        let output = state.markdownSyncCoordinator.reissueAfterRelayout(map: state.currentMarkdownSyncMap())
        state.applyMarkdownSyncOutput(output)
    }

    private func previewDidScroll(_ scrollTop: CGFloat) {
        guard presentationMode == .split,
              state.markdownViewMode == .split,
              state.markdownScrollSyncEnabled
        else { return }
        if state.markdownScrollDriver != .preview {
            state.markdownScrollDriver = .preview
        }
        state.applyMarkdownSyncOutput(
            state.markdownSyncCoordinator.previewDidScroll(scrollTop: scrollTop, map: state.currentMarkdownSyncMap())
        )
    }
}

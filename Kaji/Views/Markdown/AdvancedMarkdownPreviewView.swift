import AppKit
import SwiftUI

struct AdvancedMarkdownPreviewView: View {
    @Bindable var state: EditorTabState
    let content: String
    let presentationMode: EditorMarkdownViewMode
    let projectID: UUID?
    @Environment(AppState.self) private var appState
    @Environment(AppTypographySettings.self) private var typography

    var body: some View {
        MarkdownPreviewRepresentable(
            identity: previewIdentity,
            payload: payload,
            scrollRequestVersion: state.markdownPreviewScrollRequestVersion,
            scrollRequest: state.markdownPreviewScrollRequest,
            onMetrics: applyMetrics,
            onScroll: previewDidScroll,
            onReady: {},
            onLink: handleLink
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
            allowedRootURL: allowedRootURL,
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

    private var allowedRootURL: String {
        URL(fileURLWithPath: state.projectPath, isDirectory: true).absoluteString
    }

    private var documentURL: URL? {
        guard !state.filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: state.filePath)
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

    private func handleLink(_ request: MarkdownPreviewLinkRequest) {
        let action = MarkdownPreviewLinkResolver.resolve(
            request,
            documentURL: documentURL,
            allowedRoot: URL(fileURLWithPath: state.projectPath, isDirectory: true)
        )
        handleLinkAction(action)
    }

    private func handleLinkAction(_ action: MarkdownPreviewLinkAction) {
        switch action {
        case .anchor,
             .ignored:
            return
        case let .localFile(url):
            guard let projectID else {
                NSWorkspace.shared.open(url)
                return
            }
            appState.openFile(url.path, projectID: projectID)
        case let .external(url):
            NSWorkspace.shared.open(url)
        case let .missingLocalFile(url):
            ToastState.shared.show("Markdown link target not found: \(url.lastPathComponent)")
        case .blockedLocalFile:
            ToastState.shared.show("Markdown link is outside this project")
        case let .unsupported(url):
            ToastState.shared.show("Unsupported markdown link: \(url.scheme ?? "unknown")")
        }
    }
}

import SwiftUI

struct ParentAgentStreamingText: View {
    let content: String
    var size: CGFloat = 13
    var color: Color = KajiTheme.fgMuted
    @State private var renderedContent = ""
    @State private var pendingContent = ""
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        Text(renderedContent.isEmpty ? content : renderedContent)
            .kajiFont(size: size)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .onAppear { renderedContent = content }
            .onDisappear { renderTask?.cancel() }
            .onChange(of: content) { _, newValue in
                scheduleRender(newValue)
            }
    }

    private func scheduleRender(_ value: String) {
        pendingContent = value
        guard renderTask == nil else { return }
        renderTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            renderedContent = pendingContent
            renderTask = nil
        }
    }
}

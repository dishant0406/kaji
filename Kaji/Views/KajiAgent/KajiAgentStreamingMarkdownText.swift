import SwiftUI

struct KajiAgentStreamingMarkdownText: View {
    let messageID: UUID
    let content: String
    var size: CGFloat = 13
    var color: Color = KajiTheme.fgMuted
    @State private var snapshot = KajiAgentStreamingMarkdownSnapshot.empty
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: KajiAgentTranscriptMetrics.paragraphSpacing) {
            ForEach(snapshot.blocks) { block in
                KajiAgentMarkdownBlocksView(blocks: block.blocks, size: size, color: color)
                    .id(block.id)
                    .transaction { transaction in
                        if block.isLive { transaction.animation = nil }
                    }
            }
        }
        .textSelection(.enabled)
        .onAppear { render(content, delay: .zero) }
        .onDisappear { renderTask?.cancel() }
        .onChange(of: content) { _, newValue in render(newValue, delay: .milliseconds(32)) }
    }

    private func render(_ value: String, delay: Duration) {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            if delay != .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let next = KajiAgentStreamingMarkdownCache.shared.snapshot(
                messageID: messageID,
                content: value,
                isComplete: false
            )
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                snapshot = next
            }
        }
    }
}

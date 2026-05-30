import SwiftUI

struct GitCommitFlowView: View {
    let state: GitCommitFlowState
    let onMessageChange: (String) -> Void
    let onCommit: () -> Void
    let onRegenerate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if state.stage == .reviewMessage {
                messageEditor
            } else if state.stage == .committing {
                progress("Committing")
            } else if state.stage == .result {
                result
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(KajiMotion.panel, value: state.stage)
        .kajiChangeFeedback(state.errorText == nil ? KajiMotion.successFeedback : KajiMotion.invalidFeedback, value: state.stage, isEnabled: state.stage == .result)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text(detail)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(2)
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isGenerating {
                HStack(spacing: 8) {
                    KajiSpinner(size: 12)
                    Text("Refining with Kaji Agent")
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            } else if let generationText = state.generationText {
                Text(generationText)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            KajiTextArea(
                placeholder: "Commit message",
                text: Binding(
                    get: { state.message },
                    set: { onMessageChange($0) }
                ),
                minHeight: 130,
                maxHeight: 170,
                onSubmit: onCommit
            )
            actions
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(KajiTheme.fgMuted)
            if state.generatedMessage != nil || state.isGenerating {
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(.plain)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .disabled(state.isGenerating)
            }
            Spacer()
            Button("Commit", action: onCommit)
                .buttonStyle(.plain)
                .foregroundStyle(KajiTheme.accent)
        }
        .kajiFont(size: 12, weight: .semibold)
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            KajiSpinner(size: 14)
            Text(text)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
        }
    }

    private var result: some View {
        Text(state.errorText ?? state.statusText ?? "Done")
            .kajiFont(size: 12)
            .foregroundStyle(state.errorText == nil ? KajiTheme.diffAddFg : KajiTheme.diffRemoveFg)
            .textSelection(.enabled)
    }

    private var title: String {
        switch state.stage {
        case .reviewMessage:
            "Commit message"
        case .committing:
            "Creating commit"
        case .result:
            state.errorText == nil ? "Commit complete" : "Commit failed"
        default:
            "Commit"
        }
    }

    private var detail: String {
        let count = state.selectedPaths.count
        let selection = "\(count) selected file\(count == 1 ? "" : "s")"
        if let error = state.errorText { return error }
        return state.statusText ?? selection
    }
}

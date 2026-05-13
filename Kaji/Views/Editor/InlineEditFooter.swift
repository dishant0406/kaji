import SwiftUI

struct InlineEditFooter: View {
    let copiedAskPrompt: Bool
    let isGenerating: Bool
    let canGenerate: Bool
    let canApply: Bool
    let onReject: () -> Void
    let onCopyAskPrompt: () -> Void
    let onOpenInAsk: () -> Void
    let onGenerate: () -> Void
    let onStop: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Selected text will be replaced exactly.")
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer()
            Button("Reject", action: onReject)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button(copiedAskPrompt ? "Copied Ask Prompt" : "Copy Ask Prompt", action: onCopyAskPrompt)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button("Open in Ask", action: onOpenInAsk)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button(isGenerating ? "Stop" : "Generate") {
                isGenerating ? onStop() : onGenerate()
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(!isGenerating && !canGenerate)
            Button("Apply", action: onApply)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(KajiButtonStyle(.primary, size: .small))
                .disabled(!canApply)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

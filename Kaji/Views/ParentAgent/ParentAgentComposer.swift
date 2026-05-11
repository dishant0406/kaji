import SwiftUI

struct ParentAgentComposer: View {
    @Binding var prompt: String
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let isBusy: Bool
    let isReady: Bool
    let hasAttachments: Bool
    let onAttach: ([AskAttachment]) -> Void
    let onStop: () -> Void
    let onSubmit: () -> Void
    @State private var settings = ParentAgentSettingsStore.shared
    @State private var promptHeight: CGFloat = ParentAgentPromptTextView.minimumHeight

    var body: some View {
        HStack(spacing: 10) {
            Button(action: attachFromPanel, label: {
                KajiIcon(systemName: "plus", size: 14)
                    .frame(width: 24, height: 24)
            })
            .buttonStyle(.plain)
            .kajiPointer()
            .foregroundStyle(KajiTheme.fgMuted)
            .disabled(isBusy || !isReady)
            .help("Attach files")

            Rectangle()
                .fill(KajiTheme.borderStrong.opacity(0.55))
                .frame(width: 1, height: 22)

            ParentAgentPromptTextView(
                text: $prompt,
                height: $promptHeight,
                isFocused: isFocused,
                placeholder: placeholder,
                isEnabled: !isBusy && isReady,
                onSubmit: onSubmit,
                onAttach: onAttach
            )
            .frame(height: promptHeight)

            if isBusy {
                HStack(spacing: 6) {
                    KajiSpinner(size: 12)
                    Text("Working")
                        .kajiFont(size: 12, weight: .medium)
                }
                .foregroundStyle(KajiTheme.fgDim)
                Button("Stop") { onStop() }
                    .buttonStyle(.plain)
                    .kajiPointer()
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
            } else {
                trailingControls
            }

            Button(action: onSubmit) {
                KajiIcon(systemName: "arrow.up", size: 14)
                    .frame(width: 28, height: 28)
                    .background(sendBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .foregroundStyle(sendForeground)
            .disabled(!canSubmit || isBusy || !isReady)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    private var trailingControls: some View {
        HStack(spacing: 10) {
            KajiSelect(
                options: thinkingOptions,
                selection: thinkingSelection,
                width: 92,
                variant: .plain
            )
            .disabled(!settings.thinkingSupported || isBusy)
        }
    }

    private var canSubmit: Bool {
        !trimmedPrompt.isEmpty || hasAttachments
    }

    private func attachFromPanel() {
        let selected = AskAttachmentLoader.openPanel()
        guard !selected.isEmpty else { return }
        onAttach(selected)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sendBackground: Color {
        !canSubmit || !isReady ? KajiTheme.surfaceMuted : KajiTheme.fg
    }

    private var sendForeground: Color {
        canSubmit ? KajiTheme.bg : KajiTheme.fgDim
    }

    private var thinkingOptions: [KajiSelectOption<String>] {
        ParentAgentThinkingLevel.allCases.map { level in
            KajiSelectOption(id: level.rawValue, title: level.rawValue, value: level.rawValue)
        }
    }

    private var thinkingSelection: Binding<String> {
        Binding(
            get: { settings.thinkingSupported ? settings.thinkingLevel : ParentAgentThinkingLevel.off.rawValue },
            set: { settings.thinkingLevel = $0 }
        )
    }
}

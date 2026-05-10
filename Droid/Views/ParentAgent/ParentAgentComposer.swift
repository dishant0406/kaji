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
                DroidIcon(systemName: "plus", size: 14)
                    .frame(width: 24, height: 24)
            })
            .buttonStyle(.plain)
            .droidPointer()
            .foregroundStyle(DroidTheme.fgMuted)
            .disabled(isBusy || !isReady)
            .help("Attach files")

            Rectangle()
                .fill(DroidTheme.borderStrong.opacity(0.55))
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
                    DroidSpinner(size: 12)
                    Text("Working")
                        .droidFont(size: 12, weight: .medium)
                }
                .foregroundStyle(DroidTheme.fgDim)
                Button("Stop") { onStop() }
                    .buttonStyle(.plain)
                    .droidPointer()
                    .droidFont(size: 12, weight: .medium)
                    .foregroundStyle(DroidTheme.diffRemoveFg)
            } else {
                trailingControls
            }

            Button(action: onSubmit) {
                DroidIcon(systemName: "arrow.up", size: 14)
                    .frame(width: 28, height: 28)
                    .background(sendBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .droidPointer()
            .foregroundStyle(sendForeground)
            .disabled(!canSubmit || isBusy || !isReady)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    private var trailingControls: some View {
        HStack(spacing: 10) {
            DroidSelect(
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
        !canSubmit || !isReady ? DroidTheme.surfaceMuted : DroidTheme.fg
    }

    private var sendForeground: Color {
        canSubmit ? DroidTheme.bg : DroidTheme.fgDim
    }

    private var thinkingOptions: [DroidSelectOption<String>] {
        ParentAgentThinkingLevel.allCases.map { level in
            DroidSelectOption(id: level.rawValue, title: level.rawValue, value: level.rawValue)
        }
    }

    private var thinkingSelection: Binding<String> {
        Binding(
            get: { settings.thinkingSupported ? settings.thinkingLevel : ParentAgentThinkingLevel.off.rawValue },
            set: { settings.thinkingLevel = $0 }
        )
    }
}

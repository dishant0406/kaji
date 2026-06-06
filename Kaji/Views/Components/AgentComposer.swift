import SwiftUI

struct AgentComposer: View {
    @Binding var prompt: String
    @Binding var completionState: AgentComposerCompletionState
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let isBusy: Bool
    let isReady: Bool
    let hasAttachments: Bool
    let thinkingLevel: Binding<String>?
    let onAttach: ([AskAttachment]) -> Void
    let onStop: () -> Void
    let onSubmit: () -> Void
    let onCompletionMove: (Int) -> Void
    let onCompletionAccept: (Bool) -> Void
    let onCompletionDismiss: () -> Void
    @State private var promptHeight: CGFloat = AgentPromptTextView.minimumHeight

    var body: some View {
        VStack(spacing: 8) {
            if completionState.isVisible {
                AgentComposerSuggestionList(
                    suggestions: completionState.suggestions,
                    highlightedIndex: completionState.highlightedIndex,
                    onSelect: { _ in onCompletionAccept(false) }
                )
            }
            HStack(spacing: 10) {
                Button(action: attachFromPanel) {
                    KajiIcon(systemName: "plus", size: 14)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .kajiPointer()
                .foregroundStyle(KajiTheme.fgMuted)
                .disabled(isBusy || !isReady)
                .help("Attach files")

                Rectangle()
                    .fill(KajiTheme.borderStrong.opacity(0.55))
                    .frame(width: 1, height: 22)

                AgentPromptTextView(
                    text: $prompt,
                    height: $promptHeight,
                    completionState: $completionState,
                    isFocused: isFocused,
                    placeholder: placeholder,
                    isEnabled: !isBusy && isReady,
                    onSubmit: onSubmit,
                    onAttach: onAttach,
                    onCompletionMove: onCompletionMove,
                    onCompletionAccept: onCompletionAccept,
                    onCompletionDismiss: onCompletionDismiss
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
                } else if let thinkingLevel {
                    KajiSelect(options: thinkingOptions, selection: thinkingLevel, width: 92, variant: .plain)
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
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachments
    }

    private var sendBackground: Color {
        !canSubmit || !isReady ? KajiTheme.surfaceMuted : KajiTheme.fg
    }

    private var sendForeground: Color {
        canSubmit ? KajiTheme.bg : KajiTheme.fgDim
    }

    private var thinkingOptions: [KajiSelectOption<String>] {
        ParentAgentThinkingLevel.allCases.map { level in
            KajiSelectOption(id: level.environmentValue, title: level.rawValue, value: level.environmentValue)
        }
    }

    private func attachFromPanel() {
        let selected = AskAttachmentLoader.openPanel()
        guard !selected.isEmpty else { return }
        onAttach(selected)
    }
}

private struct AgentComposerSuggestionList: View {
    let suggestions: [AgentComposerSuggestion]
    let highlightedIndex: Int
    let onSelect: (AgentComposerSuggestion) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: suggestions.count > 6) {
            VStack(spacing: 2) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button { onSelect(suggestion) } label: {
                        HStack(spacing: 8) {
                            KajiIcon(systemName: icon(for: suggestion.kind), size: 11)
                                .foregroundStyle(index == highlightedIndex ? KajiTheme.fg : KajiTheme.fgMuted)
                                .frame(width: 15)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title)
                                    .kajiFont(size: 11, weight: .medium)
                                    .foregroundStyle(KajiTheme.fg)
                                    .lineLimit(1)
                                Text(suggestion.detail)
                                    .kajiFont(size: 10)
                                    .foregroundStyle(KajiTheme.fgDim)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if let annotation = suggestion.annotation {
                                Text(annotation)
                                    .kajiFont(size: 10, design: .monospaced)
                                    .foregroundStyle(KajiTheme.fgDim)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            index == highlightedIndex ? KajiTheme.secondaryBackground : .clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    }
                    .buttonStyle(.plain)
                    .kajiPointer()
                }
            }
        }
        .padding(8)
        .frame(maxHeight: 236)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.bg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(KajiTheme.border))
    }

    private func icon(for kind: AgentComposerSuggestion.Kind) -> String {
        switch kind {
        case .slash: "command"
        case .file: "at"
        case .promptAction: "number"
        case .skill: "wand.and.stars"
        case .history: "clock.arrow.circlepath"
        }
    }
}

import SwiftUI

struct AgentSettingsQuestionPrompt: View {
    let question: KajiAgentQuestion
    let onAnswer: (String) -> Void
    let onCancel: () -> Void
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownInlineText(content: question.title, size: 12, color: KajiTheme.fgMuted)
            if question.options.isEmpty {
                input
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(question.options, id: \.self) { option in
                        Button(option) { onAnswer(option) }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    }
                }
            }
            HStack(spacing: 8) {
                if question.options.isEmpty {
                    Button("Send") { onAnswer(answer) }
                        .buttonStyle(KajiButtonStyle(.primary, size: .small))
                        .disabled(!question.allowEmpty && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("Cancel") { onCancel() }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
        }
        .padding(12)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { answer = question.prefill ?? "" }
        .onChange(of: question.id) { answer = question.prefill ?? "" }
    }

    @ViewBuilder
    private var input: some View {
        if question.method == "editor" {
            TextEditor(text: $answer)
                .font(.system(size: 12, design: question.promptStyle ? .monospaced : .default))
                .foregroundStyle(KajiTheme.fg)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: 320, minHeight: 90, maxHeight: 120)
                .background(KajiTheme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(KajiTheme.border.opacity(0.6)))
        } else if question.isSecure {
            SecureField(question.placeholder ?? "API key", text: $answer)
                .textFieldStyle(.plain)
                .kajiFont(size: 12, design: .monospaced)
                .foregroundStyle(KajiTheme.fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 320)
                .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(KajiTheme.border.opacity(0.55)))
        } else {
            KajiInput(placeholder: question.placeholder ?? "Reply", text: $answer, width: 320)
        }
    }
}

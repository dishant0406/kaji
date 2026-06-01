import SwiftUI

struct KajiAgentQuestionPrompt: View {
    let question: KajiAgentQuestion
    let onAnswer: (String) -> Void
    var onCancel: (() -> Void)?
    @State private var answer = ""
    @State private var optionFilter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                KajiIcon(systemName: "questionmark.circle", size: 13)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 18, height: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kaji Agent needs input")
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    MarkdownInlineText(content: question.title, size: 13, color: KajiTheme.fgMuted)
                }
                Spacer(minLength: 0)
            }

            if question.method == "editor" {
                editorInput
                    .padding(.leading, 28)
            } else if question.options.isEmpty {
                inputRow
                    .padding(.leading, 28)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if question.options.count > 6 {
                        KajiInput(placeholder: "Search options", text: $optionFilter, width: 360)
                    }
                    ScrollView(.vertical, showsIndicators: question.options.count > 6) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(filteredOptions, id: \.self) { option in
                                optionButton(option)
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(max(filteredOptions.count, 1)) * 42, 220))
                }
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { answer = question.prefill ?? "" }
        .onChange(of: question.id) {
            answer = question.prefill ?? ""
            optionFilter = ""
        }
    }

    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if question.isSecure {
                SecureField(question.placeholder ?? "API key", text: $answer)
                    .textFieldStyle(.plain)
                    .kajiFont(size: 12, design: .monospaced)
                    .foregroundStyle(KajiTheme.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 360)
                    .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(KajiTheme.border.opacity(0.55)))
            } else {
                KajiInput(placeholder: question.placeholder ?? "Reply", text: $answer, width: 320)
            }
            HStack(spacing: 8) {
                Button("Send") { onAnswer(answer) }
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!question.allowEmpty && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let onCancel {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                }
            }
        }
    }

    private var editorInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $answer)
                .font(.system(size: 12, design: question.promptStyle ? .monospaced : .default))
                .foregroundStyle(KajiTheme.fg)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: 520, minHeight: 120, maxHeight: 160)
                .background(KajiTheme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(KajiTheme.border.opacity(0.6)))
            HStack(spacing: 8) {
                Button("Send") { onAnswer(answer) }
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                if let onCancel {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                }
            }
        }
    }

    private var filteredOptions: [String] {
        let filter = optionFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return question.options }
        return question.options.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    private func optionButton(_ option: String) -> some View {
        Button { onAnswer(option) } label: {
            HStack(spacing: 10) {
                Text(option)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Spacer(minLength: 0)
                KajiIcon(systemName: "arrow.right", size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }
}

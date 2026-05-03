import SwiftUI

struct ParentAgentComposer: View {
    @Binding var prompt: String
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let onNewTask: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onNewTask, label: {
                DroidIcon(systemName: "plus", size: 14)
                    .frame(width: 24, height: 24)
            })
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
            .help("New task")

            Rectangle()
                .fill(DroidTheme.borderStrong.opacity(0.55))
                .frame(width: 1, height: 22)

            TextField(placeholder, text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .droidFont(size: 13)
                .foregroundStyle(DroidTheme.fg)
                .focused(isFocused)
                .onSubmit(onSubmit)

            Button("Auto") {}
                .buttonStyle(.plain)
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgDim)

            Button(action: {}, label: {
                DroidIcon(systemName: "mic", size: 13)
                    .frame(width: 24, height: 24)
            })
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)

            Button(action: onSubmit) {
                DroidIcon(systemName: "arrow.up", size: 14)
                    .frame(width: 28, height: 28)
                    .background(sendBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(sendForeground)
            .disabled(trimmedPrompt.isEmpty)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sendBackground: Color {
        trimmedPrompt.isEmpty ? DroidTheme.surfaceMuted : DroidTheme.fg
    }

    private var sendForeground: Color {
        trimmedPrompt.isEmpty ? DroidTheme.fgDim : DroidTheme.bg
    }
}

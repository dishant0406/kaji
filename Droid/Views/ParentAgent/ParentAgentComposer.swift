import SwiftUI

struct ParentAgentComposer: View {
    @Binding var prompt: String
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let isBusy: Bool
    let onNewTask: () -> Void
    let onStop: () -> Void
    let onSubmit: () -> Void
    @State private var settings = ParentAgentSettingsStore.shared

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
                .lineLimit(1 ... 3)
                .droidFont(size: 13)
                .foregroundStyle(DroidTheme.fg)
                .focused(isFocused)
                .onSubmit(onSubmit)
                .disabled(isBusy)

            if isBusy {
                HStack(spacing: 6) {
                    DroidSpinner(size: 12)
                    Text("Working")
                        .droidFont(size: 12, weight: .medium)
                }
                .foregroundStyle(DroidTheme.fgDim)
                Button("Stop") { onStop() }
                    .buttonStyle(.plain)
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
            .foregroundStyle(sendForeground)
            .disabled(trimmedPrompt.isEmpty || isBusy)
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

            Button(action: {}, label: {
                DroidIcon(systemName: "mic", size: 13)
                    .frame(width: 24, height: 24)
            })
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
        }
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

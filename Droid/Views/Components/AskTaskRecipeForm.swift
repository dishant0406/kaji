import SwiftUI

struct AskTaskRecipeForm: View {
    @Binding var name: String
    @Binding var prompt: String
    @Binding var scope: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            SettingsInputRow(label: "Name", placeholder: "Smoke test", text: $name, width: 420)
            SettingsPickerRow<AskTaskRecipeScope>(label: "Scope", selection: $scope, width: 420)
            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fg)
                DroidTextArea(
                    placeholder: "Run tests, inspect failures, patch root cause, rerun checks",
                    text: $prompt,
                    minHeight: 150,
                    maxHeight: 180,
                    onSubmit: onSave
                )
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(DroidButtonStyle(.secondary))
                Button("Save", action: onSave)
                    .buttonStyle(DroidButtonStyle(.primary))
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

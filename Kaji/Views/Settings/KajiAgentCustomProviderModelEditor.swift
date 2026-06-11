import SwiftUI

struct KajiAgentCustomProviderModelEditor: View {
    @Binding var model: KajiAgentCustomProviderModel
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                NotificationFormRow("Model ID") {
                    KajiInput(placeholder: "myco-large", text: $model.modelID, width: 180, monospaced: true)
                }
                NotificationFormRow("Name") {
                    KajiInput(placeholder: "MyCo Large", text: $model.name, width: 170)
                }
                NotificationFormRow("Context") {
                    KajiInput(placeholder: "200000", text: $model.contextWindow, width: 100, monospaced: true)
                }
                NotificationFormRow("Max tokens") {
                    KajiInput(placeholder: "32000", text: $model.maxTokens, width: 100, monospaced: true)
                }
                Spacer(minLength: 0)
                Button("Remove", role: .destructive, action: onDelete)
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                    .padding(.top, 20)
            }
            HStack(spacing: 16) {
                toggle("Reasoning", isOn: $model.reasoning)
                toggle("Text", isOn: $model.supportsText)
                toggle("Image", isOn: $model.supportsImage)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(KajiTheme.secondaryBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: KajiShape.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.controlRadius).stroke(KajiTheme.border, lineWidth: 1))
    }

    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 7) {
            KajiSwitch(isOn: isOn)
            Text(label)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
        }
    }
}

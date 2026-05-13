import SwiftUI

struct InlineEditPromptSection: View {
    @Binding var instruction: String
    @Binding var provider: AskProvider
    @Binding var selectedModel: String
    let providers: [AskProvider]
    let models: [String]
    let isGenerating: Bool
    let generationLabel: String
    let generationError: String?
    let statusText: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Instruction")
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgMuted)
                Spacer()
                providerPicker
                modelPicker
            }
            TextField("Describe the edit you want", text: $instruction)
                .textFieldStyle(.plain)
                .kajiFont(size: 13)
                .foregroundStyle(KajiTheme.fg)
                .padding(10)
                .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { onSubmit() }
            generationStatus
        }
        .padding(14)
    }

    private var providerPicker: some View {
        Picker("Provider", selection: $provider) {
            ForEach(providers) { provider in
                Text(provider.title).tag(provider)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 150)
    }

    @ViewBuilder
    private var modelPicker: some View {
        if !models.isEmpty {
            Picker("Model", selection: $selectedModel) {
                Text("Default").tag("")
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 180)
        }
    }

    private var generationStatus: some View {
        HStack(spacing: 6) {
            if isGenerating {
                ProgressView().controlSize(.mini)
                Text("Generating replacement with \(generationLabel)...")
                    .foregroundStyle(KajiTheme.fgMuted)
            } else if let generationError {
                KajiIcon(systemName: "exclamationmark.triangle", size: 10)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
                Text(generationError)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
            } else {
                Text(statusText)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
        .kajiFont(size: 10)
    }
}

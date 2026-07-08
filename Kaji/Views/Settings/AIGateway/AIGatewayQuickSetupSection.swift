import SwiftUI

struct AIGatewayQuickSetupSection: View {
    @Binding var draft: AIGatewaySetupDraft
    let hasSavedKey: Bool
    let validationMessage: String?

    var body: some View {
        SettingsSection("Setup") {
            SettingsRow("Provider") {
                KajiSelect(options: providerOptions, selection: providerSelection, width: 320)
            }
            if draft.provider.showsEndpoint {
                SettingsInputRow(
                    label: endpointLabel,
                    placeholder: draft.provider.endpointPlaceholder,
                    text: $draft.endpoint,
                    width: 320,
                    monospaced: true
                )
            }
            SettingsInputRow(
                label: modelLabel,
                placeholder: draft.provider.defaultModelID,
                text: $draft.modelID,
                width: 320,
                monospaced: true
            )
            if draft.provider.needsKey {
                SettingsRow("API key") {
                    KajiInput(
                        placeholder: hasSavedKey ? "Saved" : "Paste key",
                        text: $draft.apiKey,
                        width: 320,
                        monospaced: true,
                        secure: true
                    )
                }
            }
            if let validationMessage {
                SettingsRow("Status") {
                    Text(validationMessage)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: 320, alignment: .leading)
                }
            }
        }
    }

    private var providerOptions: [KajiSelectOption<AIGatewaySetupProviderOption>] {
        AIGatewaySetupProviderOption.allCases.map { option in
            KajiSelectOption(id: option.id, title: option.title, value: option)
        }
    }

    private var providerSelection: Binding<AIGatewaySetupProviderOption> {
        Binding(
            get: { draft.provider },
            set: { value in
                guard value != draft.provider else { return }
                draft.provider = value
                draft.resetProviderDefaults()
            }
        )
    }

    private var endpointLabel: String {
        draft.provider == .azure ? "Resource" : "Endpoint"
    }

    private var modelLabel: String {
        draft.provider == .azure ? "Deployment" : "Model"
    }
}

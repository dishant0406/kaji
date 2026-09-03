import SwiftUI

struct KajiAgentCustomProviderEditor: View {
    @Binding var draft: KajiAgentCustomProvider
    let locksProviderID: Bool
    let isAutoMatching: Bool
    let isValidating: Bool
    let matchedAccountText: String
    let validationResult: KajiAgentCustomProviderValidation?
    let onAutoMatch: () -> Void
    let onValidate: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            basicFields
            authFields
            azureDiscoveryFields
            headersField
            modelFields
            KajiAgentCustomProviderValidationStatusView(result: validationResult)
            validationMessages
            footer
        }
        .padding(SettingsMetrics.horizontalPadding)
        .background(KajiTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.panelRadius).stroke(KajiTheme.borderStrong.opacity(0.8), lineWidth: 1))
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
    }

    private var basicFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NotificationFormRow("Provider ID") {
                    if locksProviderID {
                        Text(draft.id)
                            .kajiFont(size: 12, design: .monospaced)
                            .foregroundStyle(KajiTheme.fg)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(width: 190, alignment: .leading)
                            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
                    } else {
                        KajiInput(placeholder: "myco", text: $draft.id, width: 190, monospaced: true)
                    }
                }
                NotificationFormRow("API") {
                    KajiSelect(options: apiOptions, selection: $draft.api, width: 230)
                }
                NotificationFormRow("Discovery") {
                    KajiSelect(options: discoveryOptions, selection: $draft.discovery, width: 190)
                }
            }
            NotificationFormRow("Base URL") {
                KajiInput(placeholder: "https://api.example.com/v1", text: $draft.baseUrl, width: 500, monospaced: true)
            }
        }
    }

    private var authFields: some View {
        HStack(alignment: .top, spacing: 12) {
            NotificationFormRow("Auth") {
                KajiSelect(options: authOptions, selection: $draft.auth, width: 150)
            }
            if draft.auth == .apiKey {
                NotificationFormRow("API key env var or token") {
                    KajiInput(placeholder: apiKeyPlaceholder, text: $draft.apiKey, width: 338, monospaced: true, secure: true)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Strict tools")
                    .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgDim)
                HStack(spacing: 8) {
                    KajiSwitch(isOn: $draft.disableStrictTools)
                    Text("Disable")
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                .frame(height: 34)
            }
        }
    }

    @ViewBuilder
    private var azureDiscoveryFields: some View {
        if draft.discovery == .azureOpenAIDeployments {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    NotificationFormRow("Azure resource group") {
                        KajiInput(placeholder: "Optional", text: $draft.azureResourceGroup, width: 180, monospaced: true)
                    }
                    NotificationFormRow("Azure account") {
                        KajiInput(placeholder: "Inferred from URL", text: $draft.azureAccountName, width: 180, monospaced: true)
                    }
                    NotificationFormRow("Subscription") {
                        KajiInput(placeholder: "Optional", text: $draft.azureSubscription, width: 170, monospaced: true)
                    }
                }
                HStack(spacing: 8) {
                    Button(isAutoMatching ? "Matching..." : "Auto Match Models", action: onAutoMatch)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        .disabled(!draft.canAutoMatchModels || isAutoMatching)
                    Button(isValidating ? "Validating..." : "Validate Connection", action: onValidate)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        .disabled(!draft.canValidateConnection || isValidating)
                    Text(autoMatchHelpText)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var headersField: some View {
        NotificationFormBlock("Headers") {
            KajiTextArea(placeholder: "X-Org-Id: myco", text: $draft.headersText, minHeight: 70, maxHeight: 110, monospaced: true)
        }
    }

    private var modelFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.discovery == .none ? "Models" : "Fallback Models")
                        .kajiFont(size: SettingsMetrics.footnoteFontSize, weight: .semibold)
                        .foregroundStyle(KajiTheme.fgDim)
                    Text(modelHelpText)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                Spacer()
                Button("Add Model") { draft.models.append(KajiAgentCustomProviderModel()) }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            ForEach($draft.models) { $model in
                KajiAgentCustomProviderModelEditor(model: $model) {
                    draft.models.removeAll { $0.id == model.id }
                    if draft.models.isEmpty {
                        draft.models.append(KajiAgentCustomProviderModel())
                    }
                }
            }
        }
    }

    private var validationMessages: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(draft.validationErrors, id: \.self) { error in
                HStack(spacing: 6) {
                    KajiIcon(systemName: "xmark.circle", size: 10)
                    Text(error)
                        .kajiFont(size: 11)
                }
                .foregroundStyle(KajiTheme.diffRemoveFg)
            }
        }
    }

    private var modelHelpText: String {
        draft.discovery == .none
            ? "Manual models are required without discovery."
            : "Optional metadata overrides for discovered model IDs."
    }

    private var autoMatchHelpText: String {
        if !matchedAccountText.isEmpty {
            return matchedAccountText
        }
        return "Uses Azure CLI login to list response-capable deployments."
    }

    private var apiKeyPlaceholder: String {
        draft.apiKeyConfigured
            ? "Leave blank to keep saved key"
            : draft.discovery == .azureOpenAIDeployments ? "AZURE_OPENAI_API_KEY" : "MYCO_API_KEY"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Literal API keys are saved in OMP models.yml. Env var names are safer.")
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(KajiButtonStyle(.ghost, size: .small))
            Button(locksProviderID ? "Save" : "Create", action: onSave)
                .buttonStyle(KajiButtonStyle(.primary, size: .small))
                .disabled(!draft.canSave)
        }
    }

    private var apiOptions: [KajiSelectOption<KajiAgentCustomProviderAPI>] {
        KajiAgentCustomProviderAPI.allCases.map { KajiSelectOption(id: $0.rawValue, title: $0.title, value: $0) }
    }

    private var authOptions: [KajiSelectOption<KajiAgentCustomProviderAuth>] {
        KajiAgentCustomProviderAuth.allCases.map { KajiSelectOption(id: $0.rawValue, title: $0.title, value: $0) }
    }

    private var discoveryOptions: [KajiSelectOption<KajiAgentCustomProviderDiscovery>] {
        KajiAgentCustomProviderDiscovery.allCases.map { KajiSelectOption(id: $0.rawValue, title: $0.title, value: $0) }
    }
}

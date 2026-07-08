import SwiftUI

struct AIGatewayProvidersSection: View {
    let providers: [AIGatewayProviderConfiguration]
    let keyStatus: (String) -> Bool
    let onUpdate: (AIGatewayProviderConfiguration) -> Void
    let onSaveKey: (String, String) -> Void

    var body: some View {
        SettingsSection(
            "Providers",
            footer: "Azure OpenAI uses the v1 Responses API at resource.openai.azure.com/openai/v1. Custom Anthropic providers emit type anthropic with base_url."
        ) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                AIGatewayProviderRow(
                    provider: provider,
                    hasKey: keyStatus(provider.id),
                    isLast: index == providers.count - 1,
                    onUpdate: onUpdate,
                    onSaveKey: { onSaveKey($0, provider.id) }
                )
            }
        }
    }
}

private struct AIGatewayProviderRow: View {
    let provider: AIGatewayProviderConfiguration
    let hasKey: Bool
    let isLast: Bool
    let onUpdate: (AIGatewayProviderConfiguration) -> Void
    let onSaveKey: (String) -> Void
    @State private var draft: AIGatewayProviderConfiguration
    @State private var apiKey = ""

    init(
        provider: AIGatewayProviderConfiguration,
        hasKey: Bool,
        isLast: Bool,
        onUpdate: @escaping (AIGatewayProviderConfiguration) -> Void,
        onSaveKey: @escaping (String) -> Void
    ) {
        self.provider = provider
        self.hasKey = hasKey
        self.isLast = isLast
        self.onUpdate = onUpdate
        self.onSaveKey = onSaveKey
        _draft = State(initialValue: provider)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                KajiIcon(systemName: iconName, size: 15).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                    Text(statusText)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                Spacer(minLength: 0)
                KajiSwitch(isOn: Binding(get: { draft.isEnabled }, set: { draft.isEnabled = $0
                    commit()
                }))
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 2)

            if draft.isCustom || draft.kind == .azure {
                customFields
            }

            if draft.needsAPIKey {
                HStack(spacing: 8) {
                    KajiInput(placeholder: hasKey ? "Saved" : "API key", text: $apiKey, width: 260, monospaced: true, secure: true)
                    Button(apiKey.isEmpty ? "Clear" : "Save Key") {
                        onSaveKey(apiKey)
                        apiKey = ""
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(apiKey.isEmpty && !hasKey)
                }
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                .padding(.bottom, SettingsMetrics.rowVerticalPadding + 4)
            }

            if !isLast { Divider().padding(.horizontal, SettingsMetrics.horizontalPadding) }
        }
        .onChange(of: provider) { _, value in draft = value }
    }

    private var customFields: some View {
        VStack(spacing: 8) {
            if draft.isCustom || draft.kind == .azure {
                KajiInput(placeholder: baseURLPlaceholder, text: Binding(get: { draft.baseURL }, set: { draft.baseURL = $0
                    commit()
                }), monospaced: true)
            }
            if draft.kind == .azure {
                KajiInput(placeholder: "Azure resource name", text: Binding(get: { draft.resourceName }, set: { draft.resourceName = $0
                    commit()
                }), monospaced: true)
            }
            KajiInput(placeholder: "API key env", text: Binding(get: { draft.apiKeyEnv }, set: { draft.apiKeyEnv = $0
                commit()
            }), monospaced: true)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.bottom, SettingsMetrics.rowVerticalPadding + 4)
    }

    private var statusText: String {
        if provider.id == "ollama" { return draft.isEnabled ? "Enabled, local provider" : "Disabled" }
        if hasKey { return draft.isEnabled ? "Enabled, key saved" : "Key saved" }
        return draft.isEnabled ? "Enabled, key missing" : "No key saved"
    }

    private var iconName: String {
        provider.id == "ollama" ? "desktopcomputer" : "key"
    }

    private var baseURLPlaceholder: String {
        draft.kind == .azure ? "Optional base URL, defaults to resource.openai.azure.com/openai/v1" : "Base URL"
    }

    private func commit() {
        onUpdate(draft)
    }
}

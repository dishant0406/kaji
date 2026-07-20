import SwiftUI

struct CommitMessageSettingsSection: View {
    @Bindable var settings: GitCommitMessageSettingsStore
    let modelOptions: [KajiAgentModelOption]
    let modelRoles: [KajiAgentModelRoleAssignment]
    let onRefreshModels: () -> Void

    var body: some View {
        SettingsSection(
            "Commit Messages",
            footer: "Controls the provider, model, detail, and context used while refining generated messages."
        ) {
            SettingsRow("Provider") {
                if providerOptions.isEmpty {
                    Button("Refresh models") { onRefreshModels() }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                } else {
                    KajiSelect(options: providerOptions, selection: providerSelection, width: 320)
                }
            }

            SettingsRow("Model") {
                if selectedModelOptions.isEmpty {
                    Text("No models available for this provider")
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .frame(width: 320, alignment: .leading)
                } else {
                    KajiSelect(options: modelSelectOptions, selection: modelSelection, width: 320)
                }
            }

            SettingsRow("Detail") {
                VStack(alignment: .leading, spacing: 5) {
                    KajiSelect(options: contextOptions, selection: contextSelection, width: 320)
                    Text(settings.selectedContextLevel.detail)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                .frame(width: 320, alignment: .leading)
            }

            SettingsRow("Instructions") {
                KajiTextArea(
                    placeholder: "Prefer conventional commits. Mention product area. Add a body only for risky changes.",
                    text: instructions,
                    minHeight: 92,
                    maxHeight: 130,
                    monospaced: false
                )
                .frame(width: 320)
            }
        }
    }

    private var recommendedSelector: GitCommitMessageModelSelector? {
        GitCommitMessageModelSelection.recommendedSelector(
            currentSelector: settings.modelSelector,
            modelOptions: modelOptions,
            modelRoles: modelRoles
        )
    }

    private var providerOptions: [KajiSelectOption<String>] {
        Array(Set(modelOptions.map(\.provider))).sorted().map {
            KajiSelectOption(id: $0, title: $0, value: $0)
        }
    }

    private var selectedProviderID: String {
        settings.selectedSelector?.providerID ?? recommendedSelector?.providerID ?? ""
    }

    private var selectedModelOptions: [KajiAgentModelOption] {
        GitCommitMessageModelSelection.modelOptions(
            for: selectedProviderID,
            currentSelector: settings.modelSelector,
            modelOptions: modelOptions,
            modelRoles: modelRoles
        )
    }

    private var modelSelectOptions: [KajiSelectOption<String>] {
        selectedModelOptions.map { KajiSelectOption(id: $0.id, title: $0.modelID, value: $0.id) }
    }

    private var providerSelection: Binding<String> {
        Binding(
            get: { selectedProviderID },
            set: { provider in
                guard let option = modelOptions.first(where: { $0.provider == provider }) else { return }
                settings.modelSelector = GitCommitMessageModelSelector(providerID: option.provider, modelID: option.modelID).rawValue
            }
        )
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { settings.selectedSelector?.rawValue ?? recommendedSelector?.rawValue ?? "" },
            set: { selector in settings.modelSelector = selector }
        )
    }

    private var contextOptions: [KajiSelectOption<String>] {
        GitCommitMessageContextLevel.allCases.map {
            KajiSelectOption(id: $0.rawValue, title: $0.title, value: $0.rawValue)
        }
    }

    private var contextSelection: Binding<String> {
        Binding(
            get: { settings.contextLevel },
            set: { settings.contextLevel = $0 }
        )
    }

    private var instructions: Binding<String> {
        Binding(
            get: { settings.customInstructions },
            set: { settings.customInstructions = $0 }
        )
    }
}

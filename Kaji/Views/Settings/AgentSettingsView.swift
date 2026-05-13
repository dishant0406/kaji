import SwiftUI

struct AgentSettingsView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(AppState.self) private var appState
    @State private var parentSettings = ParentAgentSettingsStore.shared
    @State private var oauthLogin = ParentAgentOAuthLoginService.shared
    @State private var selectedProjectID = ""

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Parent Agent",
                footer: "The parent model plans and calls Kaji tools. "
                    + "Worker agents are enabled in Coding Agents."
            ) {
                SettingsToggleRow(label: "Enable parent agent", isOn: parentAgentEnabled)

                SettingsRow("Status") {
                    ParentAgentReadinessBadge(readiness: parentSettings.readiness)
                }

                SettingsRow("Provider") {
                    KajiSelect(
                        options: providerOptions,
                        selection: providerSelection,
                        width: 320
                    )
                }

                SettingsRow("Model") {
                    KajiSelect(
                        options: modelOptions,
                        selection: modelSelection,
                        width: 320
                    )
                }

                SettingsRow("Auth") {
                    ParentAgentAuthBadge(status: parentSettings.authStatus)
                }

                SettingsRow("Thinking") {
                    KajiSelect(
                        options: thinkingOptions,
                        selection: thinkingSelection,
                        width: 320
                    )
                    .disabled(!parentSettings.thinkingSupported)
                }

                if parentSettings.provider.oauthKey != nil {
                    SettingsRow("OAuth") {
                        oauthControls
                    }
                }

                if oauthLogin.promptMessage != nil {
                    SettingsRow("Code") {
                        HStack(spacing: 8) {
                            KajiInput(
                                placeholder: oauthPromptPlaceholder,
                                text: $oauthLogin.promptValue,
                                width: 228,
                                monospaced: true
                            )
                            Button("Submit") {
                                oauthLogin.submitPromptValue()
                            }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                            .disabled(oauthLogin.promptValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .frame(width: 320, alignment: .leading)
                    }
                }
            }

            SettingsSection(
                "Verification",
                footer: "Set a project-specific command for Verify Run. Leave blank to auto-detect Swift packages "
                    + "and run swift build && swift test."
            ) {
                SettingsRow("Project") {
                    KajiSelect(
                        options: projectOptions,
                        selection: $selectedProjectID,
                        width: 320
                    )
                }

                SettingsInputRow(
                    label: "Verify command",
                    placeholder: "swift build && swift test",
                    text: verificationCommand,
                    width: 320,
                    monospaced: true
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: selectDefaultProject)
        .onChange(of: projectStore.projects.map(\.id)) { _, _ in selectDefaultProject() }
    }

    private var selectedProject: Project? {
        projectStore.projects.first { $0.id.uuidString == selectedProjectID }
    }

    private var parentAgentEnabled: Binding<Bool> {
        Binding(
            get: { parentSettings.isEnabled },
            set: { parentSettings.isEnabled = $0 }
        )
    }

    private var providerOptions: [KajiSelectOption<String>] {
        ParentAgentProviderRegistry.providers.map { provider in
            KajiSelectOption(id: provider.id, title: provider.title, value: provider.id)
        }
    }

    private var modelOptions: [KajiSelectOption<String>] {
        parentSettings.modelOptions.map { model in
            KajiSelectOption(id: model, title: model, value: model)
        }
    }

    private var providerSelection: Binding<String> {
        Binding(
            get: { parentSettings.providerID },
            set: { parentSettings.providerID = $0 }
        )
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { parentSettings.modelID },
            set: { parentSettings.modelID = $0 }
        )
    }

    private var thinkingOptions: [KajiSelectOption<String>] {
        ParentAgentThinkingLevel.allCases.map { level in
            KajiSelectOption(id: level.rawValue, title: level.rawValue, value: level.rawValue)
        }
    }

    private var thinkingSelection: Binding<String> {
        Binding(
            get: { parentSettings.thinkingSupported ? parentSettings.thinkingLevel : ParentAgentThinkingLevel.off.rawValue },
            set: { parentSettings.thinkingLevel = $0 }
        )
    }

    private var oauthControls: some View {
        HStack(spacing: 8) {
            if parentSettings.authStatus.configured {
                HStack(spacing: 6) {
                    KajiIcon(systemName: "checkmark.circle", size: 12)
                        .foregroundStyle(KajiTheme.diffAddFg)
                    Text("Connected")
                        .kajiFont(size: 12, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                }
            } else {
                Button(oauthLogin.isRunning ? "Connecting" : "Connect") {
                    oauthLogin.login(provider: parentSettings.provider)
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .disabled(oauthLogin.isRunning)
            }

            Text(oauthStatusText)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
    }

    private var oauthStatusText: String {
        if !oauthLogin.statusMessage.isEmpty {
            return oauthLogin.statusMessage
        }
        return parentSettings.authStatus.configured ? parentSettings.authStatus.label : "Uses Pi OAuth"
    }

    private var oauthPromptPlaceholder: String {
        oauthLogin.promptPlaceholder.isEmpty ? "Paste code or redirect URL" : oauthLogin.promptPlaceholder
    }

    private var projectOptions: [KajiSelectOption<String>] {
        projectStore.projects.map { project in
            KajiSelectOption(id: project.id.uuidString, title: project.name, value: project.id.uuidString)
        }
    }

    private var verificationCommand: Binding<String> {
        Binding(
            get: { selectedProject?.verificationCommand ?? "" },
            set: { value in
                guard let id = UUID(uuidString: selectedProjectID) else { return }
                projectStore.setVerificationCommand(id: id, to: value)
            }
        )
    }

    private func selectDefaultProject() {
        if projectStore.projects.contains(where: { $0.id.uuidString == selectedProjectID }) { return }
        selectedProjectID = appState.activeProjectID?.uuidString ?? projectStore.projects.first?.id.uuidString ?? ""
    }
}

private struct ParentAgentAuthBadge: View {
    let status: ParentAgentAuthStatus

    var body: some View {
        HStack(spacing: 6) {
            KajiIcon(systemName: status.configured ? "checkmark.circle" : "exclamationmark.triangle", size: 12)
                .foregroundStyle(status.configured ? KajiTheme.diffAddFg : KajiTheme.diffHunkFg)
            Text(status.label)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
    }
}

private struct ParentAgentReadinessBadge: View {
    let readiness: ParentAgentReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                KajiIcon(systemName: readiness.isReady ? "checkmark.circle" : "exclamationmark.triangle", size: 12)
                    .foregroundStyle(readiness.isReady ? KajiTheme.diffAddFg : KajiTheme.diffHunkFg)
                Text(readiness.title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
            }
            Text(readiness.detail)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(2)
        }
        .frame(width: 320, alignment: .leading)
    }
}

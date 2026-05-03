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
                footer: "The parent model plans and calls Droid tools. "
                    + "Worker agents such as Codex, Claude Code, and OpenCode remain separate."
            ) {
                SettingsRow("Provider") {
                    DroidSelect(
                        options: providerOptions,
                        selection: providerSelection,
                        width: 320
                    )
                }

                SettingsRow("Model") {
                    DroidSelect(
                        options: modelOptions,
                        selection: modelSelection,
                        width: 320
                    )
                }

                SettingsRow("Auth") {
                    ParentAgentAuthBadge(status: parentSettings.authStatus)
                }

                if parentSettings.provider.oauthKey != nil {
                    SettingsRow("OAuth") {
                        oauthControls
                    }
                }

                if oauthLogin.promptMessage != nil {
                    SettingsRow("Code") {
                        HStack(spacing: 8) {
                            DroidInput(
                                placeholder: oauthPromptPlaceholder,
                                text: $oauthLogin.promptValue,
                                width: 228,
                                monospaced: true
                            )
                            Button("Submit") {
                                oauthLogin.submitPromptValue()
                            }
                            .buttonStyle(DroidButtonStyle(.secondary, size: .small))
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
                    DroidSelect(
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
        .onAppear(perform: selectDefaultProject)
        .onChange(of: projectStore.projects.map(\.id)) { _, _ in selectDefaultProject() }
    }

    private var selectedProject: Project? {
        projectStore.projects.first { $0.id.uuidString == selectedProjectID }
    }

    private var providerOptions: [DroidSelectOption<String>] {
        ParentAgentProviderRegistry.providers.map { provider in
            DroidSelectOption(id: provider.id, title: provider.title, value: provider.id)
        }
    }

    private var modelOptions: [DroidSelectOption<String>] {
        parentSettings.modelOptions.map { model in
            DroidSelectOption(id: model, title: model, value: model)
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

    private var oauthControls: some View {
        HStack(spacing: 8) {
            if parentSettings.authStatus.configured {
                HStack(spacing: 6) {
                    DroidIcon(systemName: "checkmark.circle", size: 12)
                        .foregroundStyle(DroidTheme.diffAddFg)
                    Text("Connected")
                        .droidFont(size: 12, weight: .medium)
                        .foregroundStyle(DroidTheme.fg)
                }
            } else {
                Button(oauthLogin.isRunning ? "Connecting" : "Connect") {
                    oauthLogin.login(provider: parentSettings.provider)
                }
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
                .disabled(oauthLogin.isRunning)
            }

            Text(oauthStatusText)
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
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

    private var projectOptions: [DroidSelectOption<String>] {
        projectStore.projects.map { project in
            DroidSelectOption(id: project.id.uuidString, title: project.name, value: project.id.uuidString)
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
            DroidIcon(systemName: status.configured ? "checkmark.circle" : "exclamationmark.triangle", size: 12)
                .foregroundStyle(status.configured ? DroidTheme.diffAddFg : DroidTheme.diffHunkFg)
            Text(status.label)
                .droidFont(size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
    }
}

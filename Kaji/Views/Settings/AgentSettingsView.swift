import SwiftUI

struct AgentSettingsView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(AppState.self) private var appState
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var kajiAgent = KajiAgentStore()
    @State private var kajiSettings = KajiAgentSettingsStore.shared
    @State private var commitMessageSettings = GitCommitMessageSettingsStore.shared
    @State private var selectedProjectID = ""

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Kaji Agent",
                footer: "Kaji Agent uses the embedded coding-agent harness with native Kaji UI."
            ) {
                SettingsRow("Status") {
                    KajiAgentReadinessBadge(readiness: kajiAgent.readiness)
                }

                SettingsRow("Model") {
                    if kajiAgent.modelOptions.isEmpty {
                        Button("Refresh models") { refreshKajiAgentMetadata() }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    } else {
                        KajiSelect(
                            options: modelSelectOptions,
                            selection: modelSelection,
                            width: 320
                        )
                    }
                }

                if !kajiAgent.modelRoles.isEmpty {
                    ForEach(kajiAgent.modelRoles.filter { ["default", "smol", "plan", "designer", "task"].contains($0.role) }) { role in
                        SettingsRow(role.name) {
                            KajiSelect(
                                options: modelRoleOptions(for: role),
                                selection: modelRoleSelection(for: role),
                                width: 320
                            )
                        }
                    }
                }

                SettingsRow("Models") {
                    Button("Refresh") { refreshKajiAgentMetadata() }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                }

                SettingsRow("Permissions") {
                    KajiSelect(
                        options: permissionOptions,
                        selection: permissionSelection,
                        width: 320
                    )
                }

                SettingsRow("Auth") {
                    KajiAgentAuthSummary(providers: kajiAgent.loginProviders)
                }

                if let question = kajiAgent.loginQuestion ?? kajiAgent.settingsQuestion {
                    SettingsRow("Input") {
                        KajiAgentQuestionPrompt(question: question) { answer in
                            kajiAgent.answerQuestion(question, value: answer)
                        } onCancel: {
                            kajiAgent.cancelQuestion(question)
                        }
                        .frame(width: 320, alignment: .leading)
                    }
                }

                if kajiAgent.loginCode != nil || kajiAgent.loginInstructions != nil || kajiAgent.loginURL != nil {
                    SettingsRow("Device code") {
                        KajiAgentLoginInstructionsView(store: kajiAgent)
                            .frame(width: 320, alignment: .leading)
                    }
                }

                SettingsRow("Thinking") {
                    KajiSelect(
                        options: thinkingOptions,
                        selection: thinkingSelection,
                        width: 320
                    )
                }

                SettingsRow("OAuth") {
                    if kajiAgent.loginProviders.isEmpty {
                        Button("Refresh providers") { refreshKajiAgentMetadata() }
                            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    } else {
                        KajiSelect(
                            options: loginProviderOptions,
                            selection: loginSelection,
                            width: 320
                        )
                    }
                }

                SettingsRow("Login status") {
                    Text(kajiAgent.loginStatus)
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .lineLimit(2)
                        .frame(width: 320, alignment: .leading)
                }
            }

            CommitMessageSettingsSection(settings: commitMessageSettings)

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
        .onAppear {
            selectDefaultProject()
            refreshKajiAgentMetadata()
        }
        .onChange(of: projectStore.projects.map(\.id)) { _, _ in selectDefaultProject() }
    }

    private var selectedProject: Project? {
        projectStore.projects.first { $0.id.uuidString == selectedProjectID }
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { kajiAgent.modelLabel },
            set: { value in
                guard let option = kajiAgent.modelOptions.first(where: { $0.title == value || $0.id == value }) else { return }
                kajiAgent.setModel(provider: option.provider, modelID: option.modelID)
            }
        )
    }

    private var modelSelectOptions: [KajiSelectOption<String>] {
        kajiAgent.modelOptions.map { KajiSelectOption(id: $0.id, title: $0.title, value: $0.title) }
    }

    private var thinkingOptions: [KajiSelectOption<String>] {
        ParentAgentThinkingLevel.allCases.map { level in
            KajiSelectOption(id: level.environmentValue, title: level.rawValue, value: level.environmentValue)
        }
    }

    private var thinkingSelection: Binding<String> {
        Binding(
            get: { kajiAgent.thinkingLevel },
            set: { kajiAgent.setThinkingLevel($0) }
        )
    }

    private var permissionOptions: [KajiSelectOption<String>] {
        KajiAgentPermissionMode.allCases.map { mode in
            KajiSelectOption(id: mode.rawValue, title: mode.title, value: mode.rawValue)
        }
    }

    private var permissionSelection: Binding<String> {
        Binding(
            get: { kajiSettings.permissionMode },
            set: { kajiSettings.permissionMode = $0 }
        )
    }

    private var loginProviderOptions: [KajiSelectOption<String>] {
        [KajiSelectOption(id: "none", title: "Choose provider", value: "")] + kajiAgent.loginProviders.map {
            KajiSelectOption(id: $0.id, title: $0.authenticated ? "\($0.name) (connected)" : $0.name, value: $0.id)
        }
    }

    private var loginSelection: Binding<String> {
        Binding(
            get: { "" },
            set: { providerID in
                guard !providerID.isEmpty else { return }
                kajiAgent.login(providerID: providerID)
            }
        )
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

    private func refreshKajiAgentMetadata() {
        kajiAgent.configure(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        kajiAgent.requestAvailableModels { _ in }
        kajiAgent.requestModelConfig { _ in }
        kajiAgent.requestLoginProviders { _ in }
    }

    private func modelRoleOptions(for role: KajiAgentModelRoleAssignment) -> [KajiSelectOption<String>] {
        [KajiSelectOption(id: "inherit", title: role.selector ?? "Choose model", value: "")] + kajiAgent.modelOptions.map {
            KajiSelectOption(id: "\(role.role):\($0.id)", title: $0.title, value: $0.id)
        }
    }

    private func modelRoleSelection(for role: KajiAgentModelRoleAssignment) -> Binding<String> {
        Binding(
            get: { role.selector ?? "" },
            set: { value in
                guard let option = kajiAgent.modelOptions.first(where: { $0.id == value }) else { return }
                kajiAgent.setModelRole(role: role.role, provider: option.provider, modelID: option.modelID)
            }
        )
    }
}

private struct KajiAgentAuthSummary: View {
    let providers: [KajiAgentLoginProvider]

    var body: some View {
        HStack(spacing: 6) {
            let connected = providers.filter(\.authenticated).count
            KajiIcon(systemName: connected > 0 ? "checkmark.circle" : "person.badge.key", size: 12)
                .foregroundStyle(connected > 0 ? KajiTheme.diffAddFg : KajiTheme.fgDim)
            Text(summary)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(1)
        }
        .frame(width: 320, alignment: .leading)
    }

    private var summary: String {
        let connectedProviders = providers.filter(\.authenticated)
        guard !connectedProviders.isEmpty else { return "Use OAuth provider picker" }
        let modelCount = connectedProviders.reduce(0) { $0 + ($1.availableModelCount ?? 0) }
        return "\(connectedProviders.count) connected, \(modelCount) models available"
    }
}

private struct KajiAgentReadinessBadge: View {
    let readiness: KajiAgentReadiness

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

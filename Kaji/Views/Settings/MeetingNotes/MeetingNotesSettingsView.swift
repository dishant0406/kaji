import SwiftUI

struct MeetingNotesSettingsView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(AppState.self) private var appState
    @Environment(WorktreeStore.self) private var worktreeStore

    @State private var settingsStore = MeetingNotesSettingsStore.shared
    @State private var kajiAgent = KajiAgentStore()
    @State private var coordinator = MeetingNotesCoordinator.shared

    var body: some View {
        SettingsContainer {
            captureSection
            MeetingTranscriptionSettingsSection()
            privacySection
            contextSection
            modelSection
            styleSection
            readinessSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { refreshModelsAndReadiness() }
    }

    private var captureSection: some View {
        SettingsSection(
            "Capture",
            footer: "Microphone and application audio remain separate source tracks."
        ) {
            SettingsRow("Notes interval") {
                MeetingNotesIntegerControl(
                    value: settingsStore.settings.synthesisIntervalMinutes,
                    range: 1 ... 30,
                    suffix: "min"
                ) { value in
                    settingsStore.update { $0.synthesisIntervalMinutes = value }
                }
            }
            MeetingNotesSourceToggleRow(
                label: "Application audio",
                detail: "Capture audio from the application selected when recording starts.",
                isOn: systemAudioBinding,
                canDisable: settingsStore.settings.includeMicrophone
            )
            MeetingNotesSourceToggleRow(
                label: "Microphone",
                detail: "Capture the selected Mac microphone as a separate source track.",
                isOn: microphoneBinding,
                canDisable: settingsStore.settings.includeSystemAudio
            )
        }
    }

    private var privacySection: some View {
        SettingsSection(
            "Storage and privacy",
            footer: "At least one audio source must remain enabled. Captured raw audio is removed after finalization."
        ) {
            SettingsRow("Retention") {
                MeetingNotesIntegerControl(
                    value: settingsStore.settings.retentionDays,
                    range: 1 ... 3650,
                    suffix: settingsStore.settings.retentionDays == 1 ? "day" : "days"
                ) { value in
                    settingsStore.update { $0.retentionDays = value }
                }
            }
        }
    }

    private var contextSection: some View {
        SettingsSection(
            "Project context",
            footer: "Project context is never shared unless this setting is enabled."
        ) {
            SettingsDetailToggleRow(
                label: "Share project context",
                detail: "Include bounded project metadata with transcript excerpts sent to the selected notes provider.",
                isOn: binding(\.shareProjectContext)
            )
            if settingsStore.settings.shareProjectContext {
                SettingsRow("Scope") {
                    KajiSelect(
                        options: contextScopeOptions,
                        selection: contextScopeBinding,
                        width: 220
                    )
                    .accessibilityLabel("Project context scope")
                }
                MeetingNotesSettingsNotice(
                    icon: "icloud.and.arrow.up",
                    text: contextDisclosure,
                    color: KajiTheme.accent
                )
            }
        }
    }

    private var modelSection: some View {
        SettingsSection(
            "Notes model",
            footer: "Choose both values explicitly. Kaji does not automatically select a cloud provider or model."
        ) {
            SettingsRow("Provider") {
                KajiSelect(
                    options: providerOptions,
                    selection: providerSelection,
                    placeholder: "Choose provider",
                    width: 320
                )
                .accessibilityLabel("Meeting notes provider")
            }
            SettingsRow("Model") {
                if selectedProviderID.isEmpty {
                    Text("Choose a provider first")
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: 320, alignment: .leading)
                } else {
                    KajiSelect(
                        options: modelOptions,
                        selection: modelSelection,
                        placeholder: "Choose model",
                        width: 320
                    )
                    .accessibilityLabel("Meeting notes model")
                }
            }
            SettingsRow("Catalog") {
                Button("Refresh models", action: refreshModelsAndReadiness)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(coordinator.notesModelReadiness == .checking)
            }
            MeetingNotesSettingsNotice(
                icon: "network",
                text: cloudDisclosure,
                color: settingsStore.settings.isModelConfigured ? KajiTheme.fgMuted : KajiTheme.diffHunkFg
            )
        }
    }

    private var styleSection: some View {
        SettingsSection(
            "Note style",
            footer: "Instructions are limited to 2,000 characters and are sent to the selected notes provider."
        ) {
            VStack(alignment: .leading, spacing: 6) {
                KajiTextArea(
                    placeholder: "Example: Keep decisions concise and use action-oriented language.",
                    text: styleInstructionsBinding,
                    minHeight: 90,
                    maxHeight: 180
                )
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                .accessibilityLabel("Meeting notes style instructions")
                Text("\(settingsStore.settings.styleInstructions.count) / 2000")
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, SettingsMetrics.horizontalPadding)
            }
        }
    }

    private var readinessSection: some View {
        SettingsSection("Readiness", showsDivider: false) {
            SettingsRow("Notes runtime") {
                MeetingNotesReadinessValue(
                    ready: kajiAgent.readiness.isReady,
                    title: kajiAgent.readiness.title,
                    detail: kajiAgent.readiness.detail
                )
            }
            SettingsRow("Notes model") {
                HStack(alignment: .top, spacing: 8) {
                    if coordinator.notesModelReadiness == .checking {
                        KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.fgMuted)
                            .padding(.top, 2)
                    }
                    MeetingNotesReadinessValue(
                        ready: coordinator.notesModelReadiness.isReady,
                        title: coordinator.notesModelReadiness.title,
                        detail: coordinator.notesModelReadiness.detail
                    )
                }
            }
            SettingsRow("Validation") {
                Button("Recheck") {
                    Task { await coordinator.refreshNotesModelReadiness() }
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                .disabled(!settingsStore.settings.isModelConfigured || coordinator.notesModelReadiness == .checking)
            }
            if let error = settingsStore.persistenceError {
                MeetingNotesSettingsNotice(icon: "exclamationmark.triangle", text: error, color: KajiTheme.diffRemoveFg)
            }
        }
    }

    private var systemAudioBinding: Binding<Bool> {
        Binding(get: { settingsStore.settings.includeSystemAudio }, set: { enabled in
            guard enabled || settingsStore.settings.includeMicrophone else { return }
            settingsStore.update { $0.includeSystemAudio = enabled }
        })
    }

    private var microphoneBinding: Binding<Bool> {
        Binding(get: { settingsStore.settings.includeMicrophone }, set: { enabled in
            guard enabled || settingsStore.settings.includeSystemAudio else { return }
            settingsStore.update { $0.includeMicrophone = enabled }
        })
    }

    private func binding(_ keyPath: WritableKeyPath<MeetingNotesIntegrationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in settingsStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var contextScopeOptions: [KajiSelectOption<String>] {
        [
            KajiSelectOption(
                id: MeetingProjectContextScope.active.rawValue,
                title: "Active project",
                value: MeetingProjectContextScope.active.rawValue
            ),
            KajiSelectOption(
                id: MeetingProjectContextScope.all.rawValue,
                title: "All linked projects",
                value: MeetingProjectContextScope.all.rawValue
            ),
        ]
    }

    private var contextScopeBinding: Binding<String> {
        Binding(get: { settingsStore.settings.contextScope.rawValue }, set: { value in
            guard let scope = MeetingProjectContextScope(rawValue: value) else { return }
            settingsStore.update { $0.contextScope = scope }
        })
    }

    private var selectedProviderID: String {
        settingsStore.settings.notesProviderID
    }

    private var providerOptions: [KajiSelectOption<String>] {
        let providers = Array(Set(kajiAgent.modelOptions.map(\.provider))).sorted()
        return [KajiSelectOption(id: "none", title: "Choose provider", value: "")] + providers.map {
            KajiSelectOption(id: $0, title: $0, value: $0)
        }
    }

    private var providerSelection: Binding<String> {
        Binding(get: { selectedProviderID }, set: { providerID in
            guard providerID != selectedProviderID else { return }
            settingsStore.configureModel(providerID: providerID, modelID: "")
            Task { await coordinator.refreshNotesModelReadiness() }
        })
    }

    private var modelOptions: [KajiSelectOption<String>] {
        [KajiSelectOption(id: "none", title: "Choose model", value: "")] + kajiAgent.modelOptions
            .filter { $0.provider == selectedProviderID }
            .map { KajiSelectOption(id: $0.id, title: $0.modelID, value: $0.modelID) }
    }

    private var modelSelection: Binding<String> {
        Binding(get: { settingsStore.settings.notesModelID }, set: { modelID in
            guard !selectedProviderID.isEmpty else { return }
            settingsStore.configureModel(providerID: selectedProviderID, modelID: modelID)
            Task { await coordinator.refreshNotesModelReadiness() }
        })
    }

    private var styleInstructionsBinding: Binding<String> {
        Binding(get: { settingsStore.settings.styleInstructions }, set: { value in
            settingsStore.update { $0.styleInstructions = String(value.replacingOccurrences(of: "\0", with: "").prefix(2000)) }
        })
    }

    private var contextDisclosure: String {
        let scope = settingsStore.settings.contextScope == .active ? "active project" : "linked projects"
        return "Bounded metadata from the \(scope) may leave this Mac with transcript excerpts when notes are generated."
    }

    private var cloudDisclosure: String {
        guard settingsStore.settings.isModelConfigured else {
            return "Transcription remains local, but generated notes are unavailable until a provider and model are selected."
        }
        let context = settingsStore.settings.shareProjectContext ? " and enabled project context" : ""
        return "Final transcript excerpts\(context) are sent to \(settingsStore.settings.modelSelector). "
            + "macOS capture permission does not establish participant consent."
    }

    private func refreshModels() {
        kajiAgent.configure(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
        kajiAgent.requestAvailableModels { _ in }
        kajiAgent.requestModelConfig { _ in }
    }

    private func refreshModelsAndReadiness() {
        refreshModels()
        Task { await coordinator.refreshNotesModelReadiness() }
    }
}

private struct MeetingNotesSourceToggleRow: View {
    let label: String
    let detail: String
    @Binding var isOn: Bool
    let canDisable: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .kajiFont(size: SettingsMetrics.labelFontSize, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                Text(detail)
                    .kajiFont(size: SettingsMetrics.footnoteFontSize)
                    .foregroundStyle(KajiTheme.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            KajiSwitch(isOn: $isOn)
                .disabled(isOn && !canDisable)
                .accessibilityLabel(label)
                .accessibilityHint(isOn && !canDisable ? "Enable the other source before turning this source off" : detail)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }
}

struct MeetingNotesIntegerControl: View {
    let value: Int
    let range: ClosedRange<Int>
    let suffix: String
    let onChange: (Int) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { onChange(max(range.lowerBound, value - 1)) } label: {
                KajiIcon(systemName: "minus", size: 10).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(value <= range.lowerBound)
            .kajiPointer()
            .accessibilityLabel("Decrease")
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .kajiFont(size: 11, weight: .medium, design: .monospaced)
                .foregroundStyle(KajiTheme.fg)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(width: 44)
                .onSubmit(commitDraft)
                .accessibilityLabel("Value")
            Text(suffix)
                .kajiFont(size: 11, weight: .medium, design: .monospaced)
                .foregroundStyle(KajiTheme.fg)
                .frame(minWidth: 32, alignment: .leading)
            Button { onChange(min(range.upperBound, value + 1)) } label: {
                KajiIcon(systemName: "plus", size: 10).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(value >= range.upperBound)
            .kajiPointer()
            .accessibilityLabel("Increase")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .onAppear { draft = String(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                draft = String(newValue)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        guard let parsed = Int(draft) else {
            draft = String(value)
            return
        }
        let clamped = min(range.upperBound, max(range.lowerBound, parsed))
        draft = String(clamped)
        onChange(clamped)
    }
}

struct MeetingNotesSettingsNotice: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KajiIcon(systemName: icon, size: 11)
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(color.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .accessibilityElement(children: .combine)
    }
}

struct MeetingNotesReadinessValue: View {
    let ready: Bool
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ready ? KajiTheme.diffAddFg : KajiTheme.diffHunkFg)
                    .frame(width: 7, height: 7)
                Text(title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
            }
            Text(detail)
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 320, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

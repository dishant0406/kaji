import SwiftUI

struct MeetingNotesPreflightView: View {
    let onCancel: () -> Void
    let onStart: (String) -> Void

    @State private var settingsStore = MeetingNotesSettingsStore.shared
    @State private var transcriptionCatalog = MeetingTranscriptionProviderCatalog.shared
    @State private var coordinator = MeetingNotesCoordinator.shared
    @State private var title = "Meeting"
    @State private var confirmsAuthority = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                KajiLabeledField("Meeting title") {
                    KajiInput(placeholder: "Meeting", text: $title)
                        .accessibilityLabel("Meeting title")
                }
                sources
                transcription
                disclosure
                consent
                actions
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .task {
            async let transcription: Void = coordinator.refreshTranscriptionReadiness()
            async let notes: Void = coordinator.refreshNotesModelReadiness()
            _ = await (transcription, notes)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Before recording")
                .kajiFont(size: 17, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text("Review capture sources and confirm participant consent before selecting an application.")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sources: some View {
        MeetingNotesPreflightSection(title: "Selected sources", icon: "waveform") {
            Text(sourceSummary)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(hasSource ? KajiTheme.fg : KajiTheme.diffRemoveFg)
            Text("The application picker appears only after you choose Start recording.")
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
        }
    }

    private var transcription: some View {
        MeetingNotesPreflightSection(
            title: "Transcription route",
            icon: transcriptionLocallyConfigured ? "checkmark.circle" : "exclamationmark.triangle"
        ) {
            Text(transcriptionRouteSummary)
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(transcriptionLocallyConfigured ? KajiTheme.diffAddFg : KajiTheme.diffHunkFg)
            Text(rawAudioDisclosure)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                "Diarization: \(settingsStore.settings.sttDiarizationEnabled ? "on" : "off"). "
                    + "Local fallback: \(settingsStore.settings.localFallbackEnabled ? "consented" : "off")."
            )
            .kajiFont(size: 11)
            .foregroundStyle(KajiTheme.fgMuted)
            if !transcriptionLocallyConfigured {
                Text(coordinator.transcriptionReadiness.reason ?? "The selected route is not locally configured.")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.diffHunkFg)
                Button("Check local configuration") {
                    Task { await coordinator.refreshTranscriptionReadiness() }
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            if selectedTranscriptionPresentation?.viewMetadata.showsLocalModelDownloadAffordance == true,
               !transcriptionLocallyConfigured
            {
                Button("Open Speech to Text settings") {
                    NotificationCenter.default.post(name: .openSpeechToTextSettings, object: nil)
                }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
        }
    }

    private var disclosure: some View {
        MeetingNotesPreflightSection(
            title: "Notes processing",
            icon: coordinator.notesModelReadiness.isReady ? "checkmark.circle" : "exclamationmark.triangle"
        ) {
            HStack(spacing: 6) {
                if coordinator.notesModelReadiness == .checking {
                    KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.fgMuted)
                }
                Text(coordinator.notesModelReadiness.title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(coordinator.notesModelReadiness.isReady ? KajiTheme.diffAddFg : KajiTheme.diffHunkFg)
            }
            Text(coordinator.notesModelReadiness.detail)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            if !coordinator.notesModelReadiness.isReady {
                Text("Recording can still start and will continue producing a transcript. Notes readiness does not block capture.")
                    .kajiFont(size: 11, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Recheck notes model") {
                        Task { await coordinator.refreshNotesModelReadiness() }
                    }
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                    .disabled(coordinator.notesModelReadiness == .checking || !settingsStore.settings.isModelConfigured)
                    if !settingsStore.settings.isModelConfigured {
                        Button("Open Meeting Notes settings") {
                            NotificationCenter.default.post(name: .openMeetingNotesSettings, object: nil)
                        }
                        .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                    }
                }
            }
            Text(projectContextDisclosure)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(cloudDisclosure)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(localRetentionDisclosure)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var consent: some View {
        Button {
            confirmsAuthority.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                KajiIcon(systemName: confirmsAuthority ? "checkmark.square.fill" : "square", size: 16)
                    .foregroundStyle(confirmsAuthority ? KajiTheme.accent : KajiTheme.fgDim)
                Text("I confirm that I have authority to record and that required participant consent has been obtained.")
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                    .stroke(confirmsAuthority ? KajiTheme.accent.opacity(0.65) : KajiTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .kajiPointer()
        .accessibilityLabel("Confirm authority and participant consent")
        .accessibilityValue(confirmsAuthority ? "Checked" : "Not checked")
        .accessibilityRepresentation {
            Toggle("I confirm authority and participant consent", isOn: $confirmsAuthority)
        }
    }

    private var actions: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(KajiButtonStyle(.secondary))
            Spacer(minLength: 12)
            Button("Start recording") {
                coordinator.authorizeNextStart(with: coordinator.makeRecordingConsent())
                onStart(title)
            }
            .buttonStyle(KajiButtonStyle(.primary))
            .disabled(!canStart)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Opens the macOS application picker and starts only after an application is selected")
        }
    }

    private var hasSource: Bool {
        settingsStore.settings.includeSystemAudio || settingsStore.settings.includeMicrophone
    }

    private var sourceSummary: String {
        var sources: [String] = []
        if settingsStore.settings.includeSystemAudio { sources.append("Selected application audio") }
        if settingsStore.settings.includeMicrophone { sources.append("Microphone") }
        return sources.isEmpty ? "No audio source enabled" : sources.joined(separator: " and ")
    }

    private var selectedTranscriptionPresentation: MeetingTranscriptionModulePresentation? {
        transcriptionCatalog.presentation(providerID: settingsStore.settings.sttProviderID)
    }

    private var transcriptionLocallyConfigured: Bool {
        coordinator.transcriptionReadiness.state == .ready
    }

    private var transcriptionRouteSummary: String {
        let settings = settingsStore.settings
        let retention = selectedRetentionPresentation?.label ?? "Selected retention policy"
        let endpoint = settings.sttEndpointSnapshot?.displayName ?? settings.sttRegionID
        return "\(settings.sttProviderID) / \(settings.sttModelID), \(settings.sttMode.rawValue), "
            + "\(endpoint), \(retention). Locally configured; provider connectivity and entitlement are unverified."
    }

    private var rawAudioDisclosure: String {
        if !recordingDisclosure.rawAudioLeavesMac {
            return "Raw microphone and system audio do not leave this Mac for transcription."
        }
        let destination = settingsStore.settings.sttEndpointSnapshot.flatMap { snapshot in
            [snapshot.restBaseURL, snapshot.webSocketBaseURL]
                .compactMap { $0.flatMap { URL(string: $0)?.host } }
                .first
        } ?? settingsStore.settings.sttProviderID
        return "Raw \(sourceSummary.lowercased()) leaves this Mac for \(destination), with "
            + "\(selectedRetentionPresentation?.label ?? "the selected endpoint retention policy"). "
            + (selectedRetentionPresentation?.prerequisite ?? "")
    }

    private var recordingDisclosure: MeetingRecordingDisclosure {
        MeetingRecordingDisclosure(
            settings: settingsStore.settings,
            readiness: coordinator.transcriptionReadiness
        )
    }

    private var projectContextDisclosure: String {
        guard settingsStore.settings.shareProjectContext else {
            return "Project context sharing is off."
        }
        let scope = settingsStore.settings.contextScope == .active ? "the active project" : "all linked projects"
        return "Context from \(scope) may be included when generating notes: project names, worktree names, "
            + "branch names, and safe relative changed-file paths."
    }

    private var cloudDisclosure: String {
        guard settingsStore.settings.isModelConfigured else {
            return "No notes model is selected. The transcript can be recorded locally, but generated notes will be unavailable."
        }
        let context = settingsStore.settings.shareProjectContext ? " and enabled project context" : ""
        return "Final transcript excerpts, canonical notes, and user edits\(context) are sent to "
            + "\(settingsStore.settings.notesProviderID) / \(settingsStore.settings.notesModelID) to generate notes."
    }

    private var canStart: Bool {
        confirmsAuthority && hasSource && transcriptionLocallyConfigured && hasRequiredAttestation &&
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedRetentionPresentation: MeetingTranscriptionRetentionPresentation? {
        guard let presentation = selectedTranscriptionPresentation?.viewMetadata.retentionPresentations.first(where: {
            $0.retention == settingsStore.settings.sttRetention
        })
        else { return nil }
        if settingsStore.settings.sttProviderID == OpenAIMeetingTranscriptionProvider.providerID,
           settingsStore.settings.sttMode == .cloudBatch,
           settingsStore.settings.sttRetention == .none
        {
            return MeetingTranscriptionRetentionPresentation(
                retention: .none,
                label: "OpenAI transcription API no retention",
                prerequisite: "OpenAI documents no application-state or abuse-monitoring retention for this transcription API route.",
                requiredAttestation: nil
            )
        }
        return presentation
    }

    private var hasRequiredAttestation: Bool {
        guard let required = selectedRetentionPresentation?.requiredAttestation else { return true }
        if required == .openAIZeroDataRetention, settingsStore.settings.sttMode != .cloudRealtime { return true }
        return settingsStore.settings.sttAccountAttestations.contains { $0.kind == required && $0.isExact }
    }

    private var localRetentionDisclosure: String {
        "Transcripts and generated notes are retained locally for up to "
            + "\(settingsStore.settings.retentionDays) days. "
            + "Pinned sessions override expiration until unpinned or explicitly deleted."
    }
}

private struct MeetingNotesPreflightSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KajiIcon(systemName: icon, size: 13)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgDim)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(KajiTheme.secondaryBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border, lineWidth: 1))
    }
}

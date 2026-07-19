import SwiftUI

struct MeetingNotesPanel: View {
    let onClose: () -> Void

    @State private var coordinator = MeetingNotesCoordinator.shared
    @State private var selectedTab = MeetingNotesPanelTab.notes
    @State private var showsPreflight = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            if showsPreflight {
                MeetingNotesPreflightView(
                    onCancel: { showsPreflight = false },
                    onStart: startRecording
                )
            } else {
                controls
                Rectangle().fill(KajiTheme.border).frame(height: 1)
                tabContent
            }
        }
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 700, maxHeight: .infinity)
        .background(KajiTheme.tertiaryBackground)
        .task { await coordinator.prepare() }
        .onChange(of: coordinator.status) { _, status in
            if status == .recording || status == .choosingApplication || status == .starting {
                showsPreflight = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: "waveform.and.mic", size: 13)
                .foregroundStyle(KajiTheme.fgMuted)
            Text("Meeting Notes")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer(minLength: 8)
            if isRecording {
                recordingIndicator
            }
            IconButton(symbol: "xmark", accessibilityLabel: "Close Meeting Notes", action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.chrome.opacity(0.42))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let presentation = MeetingNotesStatusPresentation.resolve(coordinator.status) {
                MeetingNotesStatusBanner(presentation: presentation)
            }
            if let document = displayedDocument {
                transcriptionStatus(document.configuration)
                notesStatus(document)
            }
            HStack(spacing: 10) {
                SegmentedPicker(
                    selection: $selectedTab,
                    options: MeetingNotesPanelTab.allCases.map { ($0, $0.rawValue) }
                )
                .accessibilityLabel("Meeting Notes section")
                if isRecording {
                    Button("Stop") { Task { await coordinator.stop() } }
                        .buttonStyle(KajiButtonStyle(.danger, size: .small))
                        .keyboardShortcut(".", modifiers: .command)
                        .accessibilityLabel("Stop meeting recording")
                } else {
                    Button("Start") { showsPreflight = true }
                        .buttonStyle(KajiButtonStyle(.primary, size: .small))
                        .disabled(coordinator.status.isBusy)
                        .accessibilityHint("Opens recording consent and source review")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func transcriptionStatus(_ configuration: MeetingSessionConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STT \(configuration.transcriptionRoute.providerID) / \(configuration.transcriptionRoute.modelID)")
                .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(KajiTheme.fgMuted)
            Text(
                "\(configuration.transcriptionRoute.regionID) · "
                    + "provider retention policy · "
                    + "\(coordinator.transcriptionTrackHealth.count) track sessions"
            )
            .kajiFont(size: 9, design: .monospaced)
            .foregroundStyle(KajiTheme.fgDim)
            if !coordinator.transcriptionUsage.isEmpty {
                Text(coordinator.transcriptionUsage.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
                    .joined(separator: " · "))
                    .kajiFont(size: 9, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            if let warning = coordinator.transcriptionRateLimitWarning ?? coordinator.transcriptionWarnings.last {
                Text(warning)
                    .kajiFont(size: 9)
                    .foregroundStyle(KajiTheme.diffHunkFg)
            }
            if let state = coordinator.transcriptionTrackHealth.values
                .max(by: { $0.updatedAtMilliseconds < $1.updatedAtMilliseconds })?.state,
                state == .reconnecting || state == .rateLimited || state == .localFallback
            {
                Text(transcriptionHealthLabel(state))
                    .kajiFont(size: 9, weight: .semibold)
                    .foregroundStyle(KajiTheme.diffHunkFg)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.secondaryBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
    }

    private func notesStatus(_ document: MeetingSessionDocument) -> some View {
        let state = document.synthesisState
        let presentation = MeetingNotesSynthesisPresentation.resolve(state)
        let model = document.configuration.isModelConfigured
            ? "\(document.configuration.notesProviderID) / \(document.configuration.notesModelID)"
            : "Not configured"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(notesHealthColor(notesPresentationKind(document, fallback: presentation.kind)))
                    .frame(width: 7, height: 7)
                Text("Notes \(model)")
                    .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            Text(notesHealthTitle(document, fallback: presentation.title))
                .kajiFont(size: 9, weight: .semibold)
                .foregroundStyle(notesHealthColor(notesPresentationKind(document, fallback: presentation.kind)))
            Text("\(state.pendingSegmentIDs.count) pending · \(state.attemptCount) attempts")
                .kajiFont(size: 9, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.secondaryBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .accessibilityElement(children: .combine)
    }

    private func notesHealthTitle(_ document: MeetingSessionDocument, fallback: String) -> String {
        if document.synthesisState.status == .idle, !document.configuration.isModelConfigured {
            return "Notes model required"
        }
        return fallback
    }

    private func notesPresentationKind(
        _ document: MeetingSessionDocument,
        fallback: MeetingNotesSynthesisPresentation.Kind
    ) -> MeetingNotesSynthesisPresentation.Kind {
        if document.synthesisState.status == .idle, !document.configuration.isModelConfigured {
            return .warning
        }
        return fallback
    }

    private func notesHealthColor(_ kind: MeetingNotesSynthesisPresentation.Kind) -> Color {
        switch kind {
        case .neutral:
            KajiTheme.fgMuted
        case .active:
            KajiTheme.accent
        case .warning:
            KajiTheme.diffHunkFg
        case .error:
            KajiTheme.diffRemoveFg
        case .success:
            KajiTheme.diffAddFg
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .notes:
            MeetingNotesNotesView(document: displayedDocument)
        case .transcript:
            MeetingNotesTranscriptView(
                document: displayedDocument,
                partialSegments: Array(coordinator.partialTranscriptSegments.values),
                status: coordinator.status
            )
        case .history:
            MeetingNotesHistoryView(
                sessions: coordinator.sessions,
                selectedSessionID: coordinator.selectedDocument?.session.id
            )
        }
    }

    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(KajiTheme.diffRemoveFg)
                .frame(width: 7, height: 7)
            Text("REC \(MeetingNotesTimeFormatter.elapsed(coordinator.elapsedDuration))")
                .kajiFont(size: 10, weight: .bold, design: .monospaced)
                .foregroundStyle(KajiTheme.diffRemoveFg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(KajiTheme.diffRemoveBg.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording in progress, \(MeetingNotesTimeFormatter.elapsed(coordinator.elapsedDuration)) elapsed")
    }

    private var displayedDocument: MeetingSessionDocument? {
        coordinator.activeDocument ?? coordinator.selectedDocument
    }

    private var isRecording: Bool {
        coordinator.activeDocument != nil
    }

    private func startRecording(title: String) {
        showsPreflight = false
        selectedTab = .notes
        Task { await coordinator.start(title: title) }
    }

    private func transcriptionHealthLabel(_ state: MeetingTranscriptionTrackRuntimeState) -> String {
        switch state {
        case .reconnecting:
            "Reconnecting transcription"
        case .rateLimited:
            "Transcription rate limited"
        case .localFallback:
            "Using consented local fallback"
        default:
            "Transcription active"
        }
    }
}

private struct MeetingNotesStatusBanner: View {
    let presentation: MeetingNotesStatusPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if presentation.kind == .neutral {
                KajiSpinner(size: 11, lineWidth: 1.4, color: color)
            } else {
                Circle().fill(color).frame(width: 7, height: 7).padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                if let detail = presentation.detail {
                    Text(detail)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(color.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch presentation.kind {
        case .neutral:
            KajiTheme.fgMuted
        case .active:
            KajiTheme.diffRemoveFg
        case .warning:
            KajiTheme.diffHunkFg
        case .error:
            KajiTheme.diffRemoveFg
        }
    }
}

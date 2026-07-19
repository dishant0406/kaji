import SwiftUI

struct MeetingNotesNotesView: View {
    let document: MeetingSessionDocument?

    @State private var coordinator = MeetingNotesCoordinator.shared
    @State private var draftSessionID: UUID?
    @State private var titleDraft = ""
    @State private var summaryDraft = ""
    @State private var isDirty = false
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            if let document {
                VStack(alignment: .leading, spacing: 18) {
                    editor(document)
                    status(document)
                    MeetingNotesItemSection(
                        title: "Decisions",
                        count: document.notes.decisions.count,
                        isEmpty: document.notes.decisions.isEmpty
                    ) {
                        ForEach(document.notes.decisions) { item in
                            MeetingNotesItemCard(
                                text: item.text,
                                detail: nil,
                                evidenceCount: item.evidence.count,
                                isPinned: item.isPinned,
                                pinLabel: item.isPinned ? "Unpin decision" : "Pin decision"
                            ) {
                                Task {
                                    await coordinator.pin(
                                        sessionID: document.session.id,
                                        item: .decision(item.id),
                                        isPinned: !item.isPinned
                                    )
                                }
                            }
                        }
                    }
                    MeetingNotesItemSection(
                        title: "Actions",
                        count: document.notes.actionItems.count,
                        isEmpty: document.notes.actionItems.isEmpty
                    ) {
                        ForEach(document.notes.actionItems) { item in
                            MeetingNotesActionCard(item: item) {
                                updateAction(item, in: document)
                            } onPin: {
                                Task {
                                    await coordinator.pin(
                                        sessionID: document.session.id,
                                        item: .actionItem(item.id),
                                        isPinned: !item.isPinned
                                    )
                                }
                            }
                        }
                    }
                    MeetingNotesItemSection(
                        title: "Open questions",
                        count: document.notes.openQuestions.count,
                        isEmpty: document.notes.openQuestions.isEmpty
                    ) {
                        ForEach(document.notes.openQuestions) { item in
                            MeetingNotesItemCard(
                                text: item.text,
                                detail: item.isResolved ? "Resolved" : "Open",
                                evidenceCount: item.evidence.count,
                                isPinned: item.isPinned,
                                pinLabel: item.isPinned ? "Unpin question" : "Pin question"
                            ) {
                                Task {
                                    await coordinator.pin(
                                        sessionID: document.session.id,
                                        item: .openQuestion(item.id),
                                        isPinned: !item.isPinned
                                    )
                                }
                            }
                        }
                    }
                    MeetingNotesItemSection(
                        title: "Risks",
                        count: document.notes.risks.count,
                        isEmpty: document.notes.risks.isEmpty
                    ) {
                        ForEach(document.notes.risks) { item in
                            MeetingNotesItemCard(
                                text: item.text,
                                detail: riskDetail(item),
                                evidenceCount: item.evidence.count,
                                isPinned: item.isPinned,
                                pinLabel: item.isPinned ? "Unpin risk" : "Pin risk"
                            ) {
                                Task {
                                    await coordinator.pin(
                                        sessionID: document.session.id,
                                        item: .risk(item.id),
                                        isPinned: !item.isPinned
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MeetingNotesEmptyState(
                    icon: "doc.text",
                    title: "No meeting selected",
                    detail: "Start a meeting or choose one from History to view its notes."
                )
            }
        }
        .onAppear { synchronizeDraft(force: true) }
        .onChange(of: document?.session.id) { _, _ in synchronizeDraft(force: true) }
        .onChange(of: document?.notes.revision) { _, _ in synchronizeDraft(force: false) }
    }

    private func editor(_ document: MeetingSessionDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Editable notes")
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgDim)
                Spacer(minLength: 8)
                Text("Revision \(document.notes.revision)")
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            KajiLabeledField("Title") {
                KajiInput(placeholder: "Meeting title", text: titleBinding)
                    .accessibilityLabel("Meeting notes title")
            }
            KajiLabeledField("Summary") {
                KajiTextArea(
                    placeholder: "Summary will appear as the meeting is processed.",
                    text: summaryBinding,
                    minHeight: 108,
                    maxHeight: 220,
                    onCommandEnter: saveDraft
                )
                .accessibilityLabel("Meeting summary")
            }
            HStack {
                if isDirty {
                    Text("Generated updates remain unchanged until Save.")
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
                Spacer(minLength: 8)
                Button("Discard") { synchronizeDraft(force: true) }
                    .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                    .disabled(!isDirty || isSaving)
                Button(isSaving ? "Saving" : "Save") { saveDraft() }
                    .buttonStyle(KajiButtonStyle(.primary, size: .small))
                    .disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(14)
        .background(KajiTheme.secondaryBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.panelRadius).stroke(KajiTheme.border, lineWidth: 1))
    }

    private func status(_ document: MeetingSessionDocument) -> some View {
        let presentation = synthesisPresentation(document)
        let state = document.synthesisState
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if state.status == .generating {
                    KajiSpinner(size: 12, lineWidth: 1.5, color: synthesisColor(presentation.kind))
                } else {
                    Circle()
                        .fill(synthesisColor(presentation.kind))
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .kajiFont(size: 11, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    Text(presentation.detail)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            Text(synthesisMetadata(document))
                .kajiFont(size: 9, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.canRetry || presentation.shouldOpenSettings {
                HStack(spacing: 8) {
                    if presentation.canRetry {
                        Button("Retry now") {
                            Task { await coordinator.retrySynthesis(sessionID: document.session.id) }
                        }
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                        .disabled(state.status == .generating)
                    }
                    if presentation.shouldOpenSettings {
                        Button("Open Meeting Notes settings") {
                            NotificationCenter.default.post(name: .openMeetingNotesSettings, object: nil)
                        }
                        .buttonStyle(KajiButtonStyle(.ghost, size: .small))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(synthesisColor(presentation.kind).opacity(0.07), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .stroke(synthesisColor(presentation.kind).opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func synthesisPresentation(_ document: MeetingSessionDocument) -> MeetingNotesSynthesisPresentation {
        if document.synthesisState.status != .idle {
            return MeetingNotesSynthesisPresentation.resolve(document.synthesisState)
        }
        guard document.configuration.isModelConfigured else {
            return MeetingNotesSynthesisPresentation(
                title: "Notes model required",
                detail: "Recording still produced a transcript. Select a notes model to generate notes for future transcript segments.",
                kind: .warning,
                canRetry: document.synthesisState.isPending && document.synthesisState.status != .generating,
                shouldOpenSettings: true
            )
        }
        return MeetingNotesSynthesisPresentation.resolve(document.synthesisState)
    }

    private func synthesisMetadata(_ document: MeetingSessionDocument) -> String {
        let configuration = document.configuration
        let model = configuration.isModelConfigured
            ? "\(configuration.notesProviderID) / \(configuration.notesModelID)"
            : "Not selected"
        let state = document.synthesisState
        var values = ["Model: \(model)", "Pending: \(state.pendingSegmentIDs.count)", "Attempts: \(state.attemptCount)"]
        if let lastAttempt = state.lastAttemptAtMilliseconds {
            values.append("Last: \(MeetingNotesTimeFormatter.date(lastAttempt))")
        }
        return values.joined(separator: " · ")
    }

    private func synthesisColor(_ kind: MeetingNotesSynthesisPresentation.Kind) -> Color {
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

    private var titleBinding: Binding<String> {
        Binding(get: { titleDraft }, set: { value in
            titleDraft = String(value.replacingOccurrences(of: "\0", with: "").prefix(200))
            isDirty = true
        })
    }

    private var summaryBinding: Binding<String> {
        Binding(get: { summaryDraft }, set: { value in
            summaryDraft = String(value.replacingOccurrences(of: "\0", with: "").prefix(20000))
            isDirty = true
        })
    }

    private var canSave: Bool {
        isDirty && !isSaving && !titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func synchronizeDraft(force: Bool) {
        guard let document else {
            draftSessionID = nil
            titleDraft = ""
            summaryDraft = ""
            isDirty = false
            return
        }
        guard force || !isDirty || draftSessionID != document.session.id else { return }
        draftSessionID = document.session.id
        titleDraft = document.notes.title
        summaryDraft = document.notes.summary
        isDirty = false
    }

    private func saveDraft() {
        guard canSave, let document else { return }
        var operations: [MeetingNotesPatchOperation] = []
        if titleDraft != document.notes.title { operations.append(.setTitle(titleDraft)) }
        if summaryDraft != document.notes.summary { operations.append(.setSummary(summaryDraft)) }
        guard !operations.isEmpty else {
            isDirty = false
            return
        }
        let patch = MeetingNotesPatch(
            sessionID: document.session.id,
            baseRevision: document.notes.revision,
            operations: operations
        )
        isSaving = true
        Task {
            await coordinator.updateUserNote(patch)
            isSaving = false
            if case .failed = coordinator.status { return }
            isDirty = false
        }
    }

    private func updateAction(_ item: MeetingActionItem, in document: MeetingSessionDocument) {
        var updated = item
        updated.isCompleted.toggle()
        let patch = MeetingNotesPatch(
            sessionID: document.session.id,
            baseRevision: document.notes.revision,
            operations: [.upsertActionItem(updated)]
        )
        Task { await coordinator.updateUserNote(patch) }
    }

    private func riskDetail(_ risk: MeetingRisk) -> String {
        let severity = risk.severity.rawValue.capitalized
        guard let mitigation = risk.mitigation else { return severity }
        return "\(severity) - \(mitigation)"
    }
}

private struct MeetingNotesItemSection<Content: View>: View {
    let title: String
    let count: Int
    let isEmpty: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text("\(count)")
                    .kajiFont(size: 10, weight: .semibold, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
                Spacer(minLength: 0)
            }
            if isEmpty {
                Text("Nothing captured yet")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 7) { content }
            }
        }
    }
}

private struct MeetingNotesItemCard: View {
    let text: String
    let detail: String?
    let evidenceCount: Int
    let isPinned: Bool
    let pinLabel: String
    let onPin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let detail {
                        Text(detail)
                            .kajiFont(size: 10, weight: .medium)
                            .foregroundStyle(KajiTheme.fgMuted)
                    }
                    Label("\(evidenceCount) evidence", systemImage: "quote.bubble")
                        .labelStyle(.titleAndIcon)
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            }
            Spacer(minLength: 8)
            Button(action: onPin) {
                KajiIcon(systemName: isPinned ? "pin.fill" : "pin", size: 11)
                    .foregroundStyle(isPinned ? KajiTheme.accent : KajiTheme.fgDim)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .help(pinLabel)
            .accessibilityLabel(pinLabel)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.secondaryBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border.opacity(0.8), lineWidth: 1))
    }
}

private struct MeetingNotesActionCard: View {
    let item: MeetingActionItem
    let onToggle: () -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                KajiIcon(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle", size: 15)
                    .foregroundStyle(item.isCompleted ? KajiTheme.diffAddFg : KajiTheme.fgDim)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .help(item.isCompleted ? "Mark action incomplete" : "Complete action")
            .accessibilityLabel(item.isCompleted ? "Mark action incomplete" : "Complete action")
            VStack(alignment: .leading, spacing: 5) {
                Text(item.text)
                    .kajiFont(size: 12)
                    .foregroundStyle(item.isCompleted ? KajiTheme.fgMuted : KajiTheme.fg)
                    .strikethrough(item.isCompleted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let owner = item.owner {
                        Text(owner)
                            .kajiFont(size: 10, weight: .medium)
                            .foregroundStyle(KajiTheme.fgMuted)
                    }
                    if let due = item.dueAtMilliseconds {
                        Text(MeetingNotesTimeFormatter.date(due))
                            .kajiFont(size: 10)
                            .foregroundStyle(KajiTheme.fgDim)
                    }
                    Label("\(item.evidence.count) evidence", systemImage: "quote.bubble")
                        .kajiFont(size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            }
            Spacer(minLength: 8)
            Button(action: onPin) {
                KajiIcon(systemName: item.isPinned ? "pin.fill" : "pin", size: 11)
                    .foregroundStyle(item.isPinned ? KajiTheme.accent : KajiTheme.fgDim)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .accessibilityLabel(item.isPinned ? "Unpin action" : "Pin action")
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KajiTheme.secondaryBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border.opacity(0.8), lineWidth: 1))
    }
}

struct MeetingNotesEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 9) {
            KajiIcon(systemName: icon, size: 22)
                .foregroundStyle(KajiTheme.fgDim)
            Text(title)
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Text(detail)
                .kajiFont(size: 11)
                .foregroundStyle(KajiTheme.fgDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

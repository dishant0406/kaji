import SwiftUI

struct MeetingNotesHistoryView: View {
    let sessions: [MeetingSession]
    let selectedSessionID: UUID?

    @State private var coordinator = MeetingNotesCoordinator.shared
    @State private var pendingDeletion: MeetingSession?

    var body: some View {
        ScrollView {
            if sessions.isEmpty {
                MeetingNotesEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No meeting history",
                    detail: "Completed and interrupted meetings appear here."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sessions) { session in
                        MeetingNotesHistoryRow(
                            session: session,
                            isSelected: selectedSessionID == session.id,
                            isActive: coordinator.activeDocument?.session.id == session.id,
                            onSelect: { coordinator.select(sessionID: session.id) },
                            onPin: {
                                Task { await coordinator.pin(sessionID: session.id, isPinned: !session.isPinned) }
                            },
                            hasPendingSynthesis: coordinator.hasPendingSynthesis(sessionID: session.id),
                            onRetrySynthesis: {
                                Task { await coordinator.retrySynthesis(sessionID: session.id) }
                            },
                            onDelete: { pendingDeletion = session }
                        )
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            "Delete meeting?",
            isPresented: deletionPresented,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { session in
            Button(session.isPinned ? "Delete pinned meeting" : "Delete meeting", role: .destructive) {
                Task { await coordinator.delete(sessionID: session.id, includingPinned: session.isPinned) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { session in
            Text("This removes Kaji's local copy of \"\(session.title)\". Copies held by providers or backups may remain.")
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}

private struct MeetingNotesHistoryRow: View {
    let session: MeetingSession
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void
    let onPin: () -> Void
    let hasPendingSynthesis: Bool
    let onRetrySynthesis: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        if isActive {
                            Circle()
                                .fill(KajiTheme.diffRemoveFg)
                                .frame(width: 7, height: 7)
                        }
                        Text(session.title)
                            .kajiFont(size: 12, weight: .semibold)
                            .foregroundStyle(KajiTheme.fg)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 7) {
                        Text(session.lifecycle.phase.meetingNotesTitle)
                            .kajiFont(size: 10, weight: .medium)
                            .foregroundStyle(lifecycleColor)
                        Text(MeetingNotesTimeFormatter.date(session.lifecycle.createdAtMilliseconds))
                            .kajiFont(size: 10)
                            .foregroundStyle(KajiTheme.fgDim)
                        if hasPendingSynthesis {
                            Text("Notes pending")
                                .kajiFont(size: 10, weight: .medium)
                                .foregroundStyle(KajiTheme.diffHunkFg)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .accessibilityLabel("Select \(session.title), \(session.lifecycle.phase.meetingNotesTitle)")
            VStack(spacing: 4) {
                if hasPendingSynthesis, !isActive {
                    Button(action: onRetrySynthesis) {
                        KajiIcon(systemName: "arrow.clockwise", size: 11)
                            .foregroundStyle(KajiTheme.diffHunkFg)
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.plain)
                    .kajiPointer()
                    .help("Retry notes generation")
                    .accessibilityLabel("Retry notes generation")
                }
                Button(action: onPin) {
                    KajiIcon(systemName: session.isPinned ? "pin.fill" : "pin", size: 11)
                        .foregroundStyle(session.isPinned ? KajiTheme.accent : KajiTheme.fgDim)
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(isActive)
                .kajiPointer()
                .help(session.isPinned ? "Unpin meeting" : "Pin meeting")
                .accessibilityLabel(session.isPinned ? "Unpin meeting" : "Pin meeting")
                Button(action: onDelete) {
                    KajiIcon(systemName: "trash", size: 11)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(isActive)
                .kajiPointer()
                .help("Delete meeting")
                .accessibilityLabel("Delete meeting")
            }
        }
        .padding(11)
        .background(
            isSelected ? KajiTheme.accentSoft.opacity(0.55) : KajiTheme.secondaryBackground.opacity(0.52),
            in: RoundedRectangle(cornerRadius: KajiShape.tileRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.tileRadius)
                .stroke(isSelected ? KajiTheme.accent.opacity(0.45) : KajiTheme.border, lineWidth: 1)
        )
    }

    private var lifecycleColor: Color {
        switch session.lifecycle.phase {
        case .recording,
             .paused:
            KajiTheme.diffRemoveFg
        case .interrupted:
            KajiTheme.diffHunkFg
        case .ready,
             .completed:
            KajiTheme.fgMuted
        }
    }
}

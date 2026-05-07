import SwiftUI

struct DroidCodeGraphAgentPanel: View {
    let session: DroidCodeGraphAgentSession
    let onHide: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            DroidCodeGraphAgentSessionView(session: session, onClose: onClose)
        }
        .background(DroidTheme.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            DroidIcon(systemName: "point.3.connected.trianglepath.dotted", size: 14)
                .foregroundStyle(DroidTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("DroidCodeGraph Agent")
                    .droidFont(size: 13, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text(session.subtitle)
                    .droidFont(size: 11)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            Spacer()
            statusDot
            Button {
                onHide()
            } label: {
                DroidIcon(systemName: "sidebar.right", size: 12)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
            .help("Hide graph-agent split")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor(session.status))
            .frame(width: 7, height: 7)
    }

    private func statusColor(_ status: ParentAgentTaskStatus) -> Color {
        switch status {
        case .completed: DroidTheme.diffAddFg
        case .failed,
             .cancelled: DroidTheme.diffRemoveFg
        case .waitingForUser: DroidTheme.accent
        case .planning,
             .running,
             .stale: DroidTheme.fgMuted
        }
    }
}

import SwiftUI

struct KajiCodeGraphAgentPanel: View {
    let session: KajiCodeGraphAgentSession
    let onHide: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            KajiCodeGraphAgentSessionView(session: session, onClose: onClose)
        }
        .background(KajiTheme.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: "point.3.connected.trianglepath.dotted", size: 14)
                .foregroundStyle(KajiTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("KajiCodeGraph Agent")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text(session.subtitle)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
            statusDot
            Button {
                onHide()
            } label: {
                KajiIcon(systemName: "sidebar.right", size: 12)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .foregroundStyle(KajiTheme.fgMuted)
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
        case .completed: KajiTheme.diffAddFg
        case .failed,
             .cancelled: KajiTheme.diffRemoveFg
        case .waitingForUser: KajiTheme.accent
        case .planning,
             .running,
             .stale: KajiTheme.fgMuted
        }
    }
}

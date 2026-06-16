import SwiftUI

struct KajiAgentRunStatusBar: View {
    let modelLabel: String
    let permissionTitle: String
    let readiness: KajiAgentReadiness
    let statusMessage: String
    let isRunning: Bool
    let hasInspector: Bool
    let onModel: () -> Void
    let onPermission: () -> Void
    let onNewThread: () -> Void
    let onReadiness: () -> Void
    let onToggleInspector: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            stateIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(isRunning ? statusMessage.nilIfEmpty ?? "Kaji Agent is working" : "Kaji Agent")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(modelLabel)
                    Text(permissionTitle)
                    Text(readiness.title)
                }
                .kajiFont(size: 11.5)
                .foregroundStyle(KajiTheme.fgDim)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            statusButton("Model", systemName: "sparkles", action: onModel)
            statusButton("Permissions", systemName: "lock", action: onPermission)
            statusButton(hasInspector ? "Hide details" : "Details", systemName: "sidebar.right", action: onToggleInspector)
            statusButton("New", systemName: "plus", action: onNewThread)
            if !readiness.isReady {
                statusButton("Retry", systemName: "arrow.clockwise", action: onReadiness)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            KajiTheme.secondaryBackground.opacity(0.46),
            in: RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.controlRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KajiAgentTranscriptMetrics.controlRadius)
                .stroke(KajiTheme.border.opacity(0.55))
        )
    }

    private var stateIndicator: some View {
        ZStack {
            Circle()
                .fill(readiness.isReady ? KajiTheme.diffAddFg.opacity(isRunning ? 0.26 : 0.16) : KajiTheme.diffRemoveFg.opacity(0.2))
                .frame(width: 24, height: 24)
            if isRunning {
                KajiSpinner(size: 11)
            } else {
                KajiIcon(systemName: readiness.isReady ? "checkmark" : "exclamationmark", size: 10)
                    .foregroundStyle(readiness.isReady ? KajiTheme.diffAddFg : KajiTheme.diffRemoveFg)
            }
        }
    }

    private func statusButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                KajiIcon(systemName: systemName, size: 10)
                Text(title)
                    .kajiFont(size: 11.5, weight: .medium)
            }
            .foregroundStyle(KajiTheme.fgMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kajiPointer()
    }
}

import SwiftUI

struct AgentMissionControlPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var activityStore = AIActivityStore.shared
    @State private var notificationStore = NotificationStore.shared
    let onDismiss: () -> Void

    private var items: [AgentMissionControlItem] {
        _ = notificationStore.readStateVersion
        return AgentMissionControlSnapshotBuilder.items(
            activities: Array(activityStore.activitiesByPaneID.values),
            notifications: notificationStore.notifications,
            projects: projectStore.projects,
            worktrees: worktreeStore.worktrees
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DroidTheme.border)
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 380, height: 420)
        .background(DroidTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.panelRadius))
    }

    private var header: some View {
        HStack(spacing: 8) {
            DroidIcon(systemName: "rectangle.stack", size: 12)
                .foregroundStyle(DroidTheme.fgMuted)
            Text("Agents")
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            DroidBadge(text: "\(items.count)", variant: items.contains { $0.status == .needsAttention } ? .warning : .neutral)
            Button(action: onDismiss) {
                DroidIcon(systemName: "xmark", size: 11)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DroidTheme.fgMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    AgentMissionControlRow(item: item) {
                        AgentMissionControlNavigator.navigate(
                            to: item,
                            appState: appState,
                            worktreeStore: worktreeStore,
                            notificationStore: notificationStore
                        )
                        onDismiss()
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(DroidTheme.bg.opacity(0.28))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            DroidIcon(systemName: "checkmark.circle", size: 22)
                .foregroundStyle(DroidTheme.fgDim)
            Text("No agent runs")
                .droidFont(size: 12, weight: .medium)
                .foregroundStyle(DroidTheme.fgMuted)
            Text("Active sessions and recent provider updates will appear here.")
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgDim)
                .multilineTextAlignment(.center)
                .frame(width: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DroidTheme.bg.opacity(0.28))
    }
}

private struct AgentMissionControlRow: View {
    let item: AgentMissionControlItem
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 9) {
                providerIcon
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .droidFont(size: 12, weight: .semibold)
                            .foregroundStyle(DroidTheme.fg)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        DroidBadge(text: item.status.title, variant: badgeVariant)
                    }
                    Text(item.detail)
                        .droidFont(size: 11)
                        .foregroundStyle(DroidTheme.fgMuted)
                        .lineLimit(2)
                    Text(item.providerName)
                        .droidFont(size: 10, design: .monospaced)
                        .foregroundStyle(DroidTheme.fgDim)
                    if !item.transcriptEntries.isEmpty {
                        transcriptPreview
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(hovered ? DroidTheme.hover : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(item.title), \(item.status.title)")
    }

    private var providerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .fill(DroidTheme.surface.opacity(0.5))
            ProviderIconView(iconName: item.providerIconName, size: 14, style: .monochrome(DroidTheme.fgMuted))
        }
        .frame(width: 26, height: 26)
        .overlay {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(DroidTheme.border.opacity(0.7), lineWidth: 1)
        }
    }

    private var badgeVariant: DroidBadgeVariant {
        switch item.status {
        case .running:
            .accent
        case .needsAttention:
            .warning
        case .failed:
            .danger
        case .completed,
             .notice:
            .neutral
        }
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(item.transcriptEntries.suffix(3)) { entry in
                HStack(alignment: .top, spacing: 5) {
                    Text(entry.kind.uppercased())
                        .droidFont(size: 8, weight: .semibold, design: .monospaced)
                        .foregroundStyle(DroidTheme.fgDim)
                        .frame(width: 42, alignment: .leading)
                    Text(entry.text)
                        .droidFont(size: 10)
                        .foregroundStyle(DroidTheme.fgMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(6)
        .background(DroidTheme.surface.opacity(0.38), in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(DroidTheme.border.opacity(0.6), lineWidth: 1)
        }
    }
}

import SwiftUI

struct AgentMissionControlPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var runStore = AgentRunStore.shared
    @State private var notificationStore = NotificationStore.shared
    let onDismiss: () -> Void

    private var items: [AgentMissionControlItem] {
        _ = notificationStore.readStateVersion
        return AgentRunMissionControlSnapshotBuilder.items(
            runs: runStore.runs,
            notifications: notificationStore.notifications,
            projects: projectStore.projects,
            worktrees: worktreeStore.worktrees
        )
    }

    private var sections: [AgentMissionControlSection] {
        AgentMissionControlSectionBuilder.sections(for: items)
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
                ForEach(sections) { section in
                    AgentMissionControlSectionHeader(section: section)
                    ForEach(section.items, id: \.rowIdentity) { item in
                        let capabilities = AgentControlCenter.capabilities(for: item)
                        AgentMissionControlRow(
                            item: item,
                            capabilities: capabilities,
                            onVerify: verify(item, capabilities: capabilities),
                            onOpenFile: openFile(item, capabilities: capabilities),
                            onOpenDiff: openDiff(item, capabilities: capabilities)
                        ) {
                            _ = controlCenter.perform(.jump(item))
                            onDismiss()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(DroidTheme.bg.opacity(0.28))
    }

    private var controlCenter: AgentControlCenter {
        AgentControlCenter(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
    }

    private func verify(_ item: AgentMissionControlItem, capabilities: AgentRunCapabilities) -> (() -> Void)? {
        guard let runID = item.runID else { return nil }
        guard capabilities.verify.isVisible else { return nil }
        return {
            _ = controlCenter.perform(.verify(runID))
        }
    }

    private func openFile(_ item: AgentMissionControlItem, capabilities: AgentRunCapabilities) -> ((AgentChangedFile) -> Void)? {
        guard let runID = item.runID else { return nil }
        guard capabilities.openFiles.isVisible else { return nil }
        return { file in
            _ = controlCenter.perform(.openFile(runID, file))
            onDismiss()
        }
    }

    private func openDiff(_ item: AgentMissionControlItem, capabilities: AgentRunCapabilities) -> ((AgentChangedFile) -> Void)? {
        guard let runID = item.runID else { return nil }
        guard capabilities.openDiffs.isVisible else { return nil }
        return { file in
            _ = controlCenter.perform(.openDiff(runID, file))
            onDismiss()
        }
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

private extension AgentMissionControlItem {
    var rowIdentity: String {
        "\(id)|\(status.rawValue)"
    }
}

import SwiftUI

struct AgentCommandCenterOverlay: View {
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var runStore = AgentRunStore.shared
    @State private var notificationStore = NotificationStore.shared
    @State private var query = ""
    @State private var highlightedIndex: Int? = 0
    @State private var replyTarget: AgentMissionControlItem?

    var body: some View {
        ZStack {
            DroidTheme.bg.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            panel
        }
        .onChange(of: query) { _, _ in highlightedIndex = filteredEntries.isEmpty ? nil : 0 }
        .accessibilityAddTraits(.isModal)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(DroidTheme.border.opacity(0.75))
            list
            Divider().overlay(DroidTheme.border.opacity(0.75))
            footer
        }
        .frame(width: 620, height: 430)
        .background(DroidTheme.bg)
        .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.modalRadius)
                .stroke(DroidTheme.borderStrong.opacity(0.82), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            DroidIcon(systemName: replyTarget == nil ? "rectangle.stack" : "arrowshape.turn.up.left", size: 12)
                .foregroundStyle(DroidTheme.fgDim)
            PaletteSearchField(
                text: $query,
                placeholder: placeholder,
                fontSize: 14,
                onSubmit: submit,
                onSubmitText: { _ in submit() },
                onEscape: escape,
                onArrowUp: { moveHighlight(-1) },
                onArrowDown: { moveHighlight(1) }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var list: some View {
        AgentCommandCenterList(
            sections: filteredSections,
            highlightedEntryID: highlightedEntryID,
            highlightedIndex: highlightedIndex,
            entries: filteredEntries
        )
    }

    private var footer: some View {
        Text(replyTarget == nil ? "up/down select - enter run action - esc close" : "enter send - esc cancel reply")
            .droidFont(size: 11)
            .foregroundStyle(DroidTheme.fgDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    private var placeholder: String {
        if let replyTarget { return "Reply to \(replyTarget.title)" }
        return "Search agent actions"
    }

    private var items: [AgentMissionControlItem] {
        _ = notificationStore.readStateVersion
        return AgentRunMissionControlSnapshotBuilder.items(
            runs: runStore.runs,
            notifications: notificationStore.notifications,
            projects: projectStore.projects,
            worktrees: worktreeStore.worktrees
        )
    }

    private var filteredEntries: [AgentCommandCenterEntry] {
        guard replyTarget == nil else { return [] }
        let entries = AgentCommandCenterEntries.entries(for: items)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.lowercased().contains(needle) || entry.detail.lowercased().contains(needle)
        }
    }

    private var filteredSections: [AgentCommandCenterSection] {
        AgentCommandCenterEntries.sections(for: filteredEntries)
    }

    private var highlightedEntryID: String? {
        guard let highlightedIndex, highlightedIndex < filteredEntries.count else { return nil }
        return filteredEntries[highlightedIndex].id
    }

    private var controlCenter: AgentControlCenter {
        AgentControlCenter(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
    }

    private func submit() {
        if let target = replyTarget, let runID = target.runID {
            let text = query
            self.replyTarget = nil
            query = ""
            Task { _ = await controlCenter.performAsync(.reply(runID, text)) }
            return
        }
        guard let highlightedIndex, highlightedIndex < filteredEntries.count else { return }
        perform(filteredEntries[highlightedIndex])
    }

    private func perform(_ entry: AgentCommandCenterEntry) {
        switch entry.action {
        case .jump:
            _ = controlCenter.perform(.jump(entry.item)); onDismiss()
        case .reply:
            replyTarget = entry.item; query = ""
        case .stop:
            guard let runID = entry.item.runID else { return }
            _ = controlCenter.perform(.stop(runID))
        case .newRun:
            guard let runID = entry.item.runID else { return }
            _ = controlCenter.perform(.restart(runID)); onDismiss()
        case .resume:
            guard let runID = entry.item.runID else { return }
            _ = controlCenter.perform(.resume(runID)); onDismiss()
        case .verify:
            guard let runID = entry.item.runID else { return }
            _ = controlCenter.perform(.verify(runID))
        case let .openFile(file):
            guard let runID = entry.item.runID else { return }
            _ = controlCenter.perform(.openFile(runID, file)); onDismiss()
        case let .openDiff(file):
            guard let runID = entry.item.runID else { return }
            _ = controlCenter.perform(.openDiff(runID, file)); onDismiss()
        }
    }

    private func escape() {
        if replyTarget != nil { replyTarget = nil; query = ""; return }
        onDismiss()
    }

    private func moveHighlight(_ delta: Int) {
        guard !filteredEntries.isEmpty else { highlightedIndex = nil; return }
        highlightedIndex = ((highlightedIndex ?? 0) + delta + filteredEntries.count) % filteredEntries.count
    }
}

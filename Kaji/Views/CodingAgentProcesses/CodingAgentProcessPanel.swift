import SwiftUI

struct CodingAgentProcessPanel: View {
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @State private var service = CodingAgentProcessMonitorService.shared
    @State private var query = ""
    @State private var pendingKill: CodingAgentProcessMatch?
    @State private var pendingGroupKill: CodingAgentProcessProviderGroup?
    @State private var pendingPatternKill: CodingAgentProcessProviderGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            KajiInput(placeholder: "Filter providers, pids, commands", text: $query, leadingIcon: "magnifyingglass", monospaced: true)
            content
            status
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 420)
        .background(KajiTheme.tertiaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .confirmationDialog(
            "Kill agent process?",
            isPresented: pendingKillPresented,
            titleVisibility: .visible,
            presenting: pendingKill
        ) { match in
            Button("Kill pid \(match.process.pid)", role: .destructive) {
                service.terminate(match, appState: appState, projectStore: projectStore)
                pendingKill = nil
            }
            Button("Cancel", role: .cancel) { pendingKill = nil }
        } message: { match in
            Text("This sends SIGTERM to \(match.providerName) process \(match.process.commandName).")
        }
        .confirmationDialog(
            "Kill all \(pendingGroupKill?.providerName ?? "agent") processes?",
            isPresented: pendingGroupKillPresented,
            titleVisibility: .visible,
            presenting: pendingGroupKill
        ) { group in
            Button("Kill \(group.processes.count) processes", role: .destructive) {
                service.terminateGroup(group, appState: appState, projectStore: projectStore)
                pendingGroupKill = nil
            }
            Button("Cancel", role: .cancel) { pendingGroupKill = nil }
        } message: { group in
            Text("This sends SIGTERM to every visible \(group.providerName) process in this list.")
        }
        .confirmationDialog(
            "Run pkill -f for \(pendingPatternKill?.providerName ?? "agent")?",
            isPresented: pendingPatternKillPresented,
            titleVisibility: .visible,
            presenting: pendingPatternKill
        ) { group in
            Button("pkill -TERM -f", role: .destructive) {
                service.patternKillGroup(group, force: false, appState: appState, projectStore: projectStore)
                pendingPatternKill = nil
            }
            Button("pkill -KILL -f", role: .destructive) {
                service.patternKillGroup(group, force: true, appState: appState, projectStore: projectStore)
                pendingPatternKill = nil
            }
            Button("Cancel", role: .cancel) { pendingPatternKill = nil }
        } message: { group in
            Text(patternKillWarning(for: group))
        }
        .task {
            service.refresh(appState: appState, projectStore: projectStore)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "cpu", size: 12)
                .foregroundStyle(service.orphanCount > 0 ? KajiTheme.diffRemoveFg : KajiTheme.fgMuted)
            Text("Agent Processes")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer(minLength: 8)
            KajiBadge(text: "\(service.processCount)", variant: service.orphanCount > 0 ? .danger : .neutral)
            refreshButton
            closeButton
        }
    }

    private var refreshButton: some View {
        Button { service.refresh(appState: appState, projectStore: projectStore) } label: {
            Group {
                if service.isRefreshing {
                    KajiSpinner(size: 12, lineWidth: 1.5)
                } else {
                    KajiIcon(systemName: "arrow.clockwise", size: 11)
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .kajiPointer()
        .foregroundStyle(KajiTheme.fgMuted)
        .disabled(service.isRefreshing)
        .help("Refresh")
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            KajiIcon(systemName: "xmark", size: 11)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .kajiPointer()
        .foregroundStyle(KajiTheme.fgMuted)
        .help("Close")
    }

    @ViewBuilder
    private var content: some View {
        if filteredGroups.isEmpty {
            Text(service.isRefreshing ? "Scanning agent processes..." : "No coding agent processes found.")
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredGroups) { group in
                        CodingAgentProcessGroupSection(
                            group: group,
                            killingPIDs: service.killingPIDs,
                            onKill: { pendingKill = $0 },
                            onKillGroup: { pendingGroupKill = group },
                            onPatternKillGroup: { pendingPatternKill = group }
                        )
                    }
                }
            }
            .frame(maxHeight: 420)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let message = service.statusMessage {
            Text(message)
                .kajiFont(size: 11)
                .foregroundStyle(service.statusIsError ? KajiTheme.diffRemoveFg : KajiTheme.fgDim)
                .lineLimit(2)
        }
    }

    private var filteredGroups: [CodingAgentProcessProviderGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return service.groups }
        return service.groups.compactMap { group in
            let processes = group.processes.filter { match in
                group.providerName.localizedCaseInsensitiveContains(trimmed) ||
                    match.process.commandName.localizedCaseInsensitiveContains(trimmed) ||
                    match.process.commandLine.localizedCaseInsensitiveContains(trimmed) ||
                    "\(match.process.pid)".contains(trimmed)
            }
            guard !processes.isEmpty else { return nil }
            return CodingAgentProcessProviderGroup(
                providerID: group.providerID,
                providerName: group.providerName,
                iconName: group.iconName,
                killPatterns: group.killPatterns,
                processes: processes
            )
        }
    }

    private var pendingKillPresented: Binding<Bool> {
        Binding(
            get: { pendingKill != nil },
            set: { if !$0 { pendingKill = nil } }
        )
    }

    private var pendingGroupKillPresented: Binding<Bool> {
        Binding(
            get: { pendingGroupKill != nil },
            set: { if !$0 { pendingGroupKill = nil } }
        )
    }

    private var pendingPatternKillPresented: Binding<Bool> {
        Binding(
            get: { pendingPatternKill != nil },
            set: { if !$0 { pendingPatternKill = nil } }
        )
    }

    private func patternKillWarning(for group: CodingAgentProcessProviderGroup) -> String {
        "Patterns: \(group.killPatterns.joined(separator: ", ")). " +
            "This can close matching sessions outside Kaji and may leave active terminals needing reset."
    }
}

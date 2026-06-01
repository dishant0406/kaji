import SwiftUI

struct KajiAgentSidebarHistorySection: View {
    let project: Project
    let worktree: Worktree
    let expanded: Bool
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var query = ""
    @State private var limit = 10
    @State private var store: KajiAgentStore?
    @State private var showingPopover = false
    @State private var sessions: [KajiAgentSessionOption] = []
    @State private var isRefreshing = false

    var body: some View {
        if expanded {
            Button {
                ensureStore()
                refresh()
                showingPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    KajiIcon(systemName: "clock.arrow.circlepath", size: 10)
                        .foregroundStyle(KajiTheme.fgDim)
                    Text("Kaji History")
                        .kajiFont(size: 11, weight: .medium)
                        .foregroundStyle(KajiTheme.fgMuted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .kajiPointer()
            .kajiPopover(isPresented: $showingPopover, preferredEdge: .trailing) {
                historyPopover
            }
            .onChange(of: showingPopover) { _, isShown in
                guard isShown else { return }
                refresh()
            }
            .task(id: worktree.id) {
                ensureStore()
                refresh()
            }
        }
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Kaji History")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer(minLength: 0)
                Button { refresh() } label: {
                    if isRefreshing {
                        KajiSpinner(size: 11)
                    } else {
                        KajiIcon(systemName: "arrow.clockwise", size: 11)
                    }
                }
                .buttonStyle(.plain)
                .kajiPointer()
                .disabled(isRefreshing)
                .help("Refresh Kaji history")
            }
            KajiInput(placeholder: "Search history", text: $query, width: 280)
                .onChange(of: query) { _, _ in refresh() }
            ScrollView(.vertical, showsIndicators: filteredSessions.count > 7) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(filteredSessions.prefix(limit)) { session in
                        Button {
                            appState.selectProject(project, worktree: worktree)
                            appState.openParentAgentTab(projectID: project.id, sessionPath: session.path)
                            showingPopover = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .kajiFont(size: 11, weight: .medium)
                                    .foregroundStyle(KajiTheme.fg)
                                    .lineLimit(1)
                                Text(session.detail)
                                    .kajiFont(size: 10)
                                    .foregroundStyle(KajiTheme.fgDim)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KajiTheme.bg.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .kajiPointer()
                    }
                    if filteredSessions.isEmpty {
                        Text("No Kaji sessions")
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgDim)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else if filteredSessions.count > limit {
                        Button("View more") { limit += 10 }
                            .buttonStyle(.plain)
                            .kajiFont(size: 11, weight: .medium)
                            .foregroundStyle(KajiTheme.fgMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .kajiPointer()
                    }
                }
            }
            .frame(height: 300)
        }
        .padding(10)
        .frame(width: 320)
    }

    private var filteredSessions: [KajiAgentSessionOption] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    private func ensureStore() {
        if store != nil { return }
        let scope = KajiAgentScope(agentID: worktree.id, projectID: project.id, worktreeID: worktree.id, projectPath: worktree.path)
        let scopedStore = KajiAgentStoreRegistry.shared.store(for: scope)
        scopedStore.configure(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore, projectPathOverride: worktree.path)
        store = scopedStore
    }

    private func refresh() {
        ensureStore()
        isRefreshing = true
        store?.requestSessions(all: false) { options in
            sessions = options
            isRefreshing = false
            KajiAgentEventLog.record("sidebar_history_refresh", fields: [
                "projectID": .string(project.id.uuidString),
                "worktreeID": .string(worktree.id.uuidString),
                "count": .number(Double(options.count)),
            ])
        }
    }
}

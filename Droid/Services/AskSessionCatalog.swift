import Foundation

@MainActor
enum AskSessionCatalog {
    static func sessions(
        projectID: UUID,
        worktreeID: UUID,
        worktrees: [Worktree],
        appState: AppState
    ) -> [AskSessionOption] {
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        guard let workspace = appState.workspaces[key] else { return [] }

        let worktreeName = worktrees.first(where: { $0.id == worktreeID }).map(displayName(for:)) ?? "main"

        return workspace.tabs.flatMap { workspaceTab in
            workspaceTab.root.allAreas().flatMap { area in
                area.tabs.compactMap { tab in
                    guard let pane = tab.content.pane else { return nil }
                    let processNames = processNames(for: pane.id)
                    return AskSessionOption(
                        projectID: projectID,
                        worktreeID: worktreeID,
                        areaID: area.id,
                        tabID: tab.id,
                        paneID: pane.id,
                        title: tab.title,
                        provider: AskProvider.detect(
                            title: tab.title,
                            startupCommand: pane.startupCommand,
                            injectedCommand: pane.injectedCommand,
                            processNames: processNames
                        ),
                        worktreeName: worktreeName
                    )
                }
            }
        }
    }

    static func filter(
        _ sessions: [AskSessionOption],
        provider: AskProvider
    ) -> [AskSessionOption] {
        sessions.filter { session in
            provider == .terminal || session.provider == provider
        }
    }

    static func bestMatch(
        in sessions: [AskSessionOption],
        provider: AskProvider
    ) -> AskSessionOption? {
        filter(sessions, provider: provider).first
    }

    nonisolated static func displayName(for worktree: Worktree) -> String {
        if worktree.isPrimary, worktree.name.isEmpty {
            return "main"
        }
        return worktree.name
    }

    private static func processNames(for paneID: UUID) -> [String] {
        guard let processGroupID = TerminalViewRegistry.shared.foregroundProcessGroupID(for: paneID) else { return [] }
        return ProcessResourceSampler.samplesForProcessGroup(id: processGroupID).map(\.processName)
    }
}

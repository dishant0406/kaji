import Foundation

@MainActor
enum AgentSessionBookmarkCatalog {
    private struct FallbackDescriptor {
        let paneID: UUID
        let providerID: String
        let paneTitle: String
        let paneProjectPath: String
        let projectID: UUID
        let worktreeID: UUID
        let worktreePath: String?
        let areaID: UUID
        let tabID: UUID
        let providerPaneCount: Int
    }

    private struct FallbackResult {
        let paneID: UUID
        let providerID: String
        let sessionID: String
        let title: String
        let projectID: UUID
        let worktreeID: UUID
        let worktreePath: String?
        let areaID: UUID
        let tabID: UUID
    }

    static func candidates(
        appState: AppState,
        worktreeStore: WorktreeStore
    ) -> [AgentSessionBookmarkCandidate] {
        guard let projectID = appState.activeProjectID,
              let worktreeID = appState.activeWorktreeID[projectID],
              let workspaceTab = appState.activeWorkspaceTab(for: projectID)
        else { return [] }

        let worktreePath = worktreeStore.worktrees[projectID]?.first { $0.id == worktreeID }?.path
            ?? appState.activeWorktreePath[projectID]

        return workspaceTab.root.allAreas().compactMap { area in
            guard let tab = area.activeTab,
                  let pane = tab.content.pane,
                  let metadata = CodingAgentSessionMetadataStore.shared.metadata(paneID: pane.id),
                  let provider = AskProvider.resolveAnnotation(metadata.providerID),
                  provider != .terminal,
                  !metadata.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return AgentSessionBookmarkCandidate(
                paneID: pane.id,
                provider: provider,
                sessionID: metadata.sessionID,
                title: metadata.title ?? tab.title,
                projectID: projectID,
                worktreeID: worktreeID,
                worktreePath: metadata.cwd ?? worktreePath,
                areaID: area.id,
                tabID: tab.id
            )
        }
    }

    static func fallbackCandidates(
        appState: AppState,
        worktreeStore: WorktreeStore
    ) async -> [AgentSessionBookmarkCandidate] {
        guard let projectID = appState.activeProjectID,
              let worktreeID = appState.activeWorktreeID[projectID],
              let workspaceTab = appState.activeWorkspaceTab(for: projectID)
        else { return [] }

        let worktreePath = worktreeStore.worktrees[projectID]?.first { $0.id == worktreeID }?.path
            ?? appState.activeWorktreePath[projectID]
        let paneProviders = workspaceTab.root.allAreas().compactMap { area -> PaneProvider? in
            guard let tab = area.activeTab,
                  let pane = tab.content.pane
            else { return nil }
            let provider = detectedProvider(tab: tab, pane: pane)
            guard provider != .terminal else { return nil }
            guard CodingAgentSessionMetadataStore.shared.metadata(paneID: pane.id) == nil else { return nil }
            return PaneProvider(area: area, tab: tab, pane: pane, provider: provider)
        }
        let providerCounts = Dictionary(grouping: paneProviders, by: { $0.provider.rawValue }).mapValues(\.count)
        let descriptors = paneProviders.map { item in
            FallbackDescriptor(
                paneID: item.pane.id,
                providerID: item.provider.rawValue,
                paneTitle: item.tab.title,
                paneProjectPath: item.pane.projectPath,
                projectID: projectID,
                worktreeID: worktreeID,
                worktreePath: worktreePath,
                areaID: item.area.id,
                tabID: item.tab.id,
                providerPaneCount: providerCounts[item.provider.rawValue] ?? 0
            )
        }
        let results = await Task.detached(priority: .userInitiated) {
            descriptors.compactMap(fallbackResult)
        }.value
        return results.map { result in
            AgentSessionBookmarkCandidate(
                paneID: result.paneID,
                provider: AskProvider(agentID: result.providerID),
                sessionID: result.sessionID,
                title: result.title,
                projectID: result.projectID,
                worktreeID: result.worktreeID,
                worktreePath: result.worktreePath,
                areaID: result.areaID,
                tabID: result.tabID
            )
        }
    }

    private struct PaneProvider {
        let area: TabArea
        let tab: TerminalTab
        let pane: TerminalPaneState
        let provider: AskProvider
    }

    private static func detectedProvider(tab: TerminalTab, pane: TerminalPaneState) -> AskProvider {
        let processNames = processNames(for: pane.id)
        return AskProvider.detect(
            title: tab.title,
            startupCommand: pane.startupCommand,
            injectedCommand: pane.injectedCommand,
            processNames: processNames
        )
    }

    private static func processNames(for paneID: UUID) -> [String] {
        guard let processGroupID = TerminalViewRegistry.shared.foregroundProcessGroupID(for: paneID) else { return [] }
        return ProcessResourceSampler.samplesForProcessGroup(id: processGroupID).map(\.processName)
    }

    nonisolated private static func fallbackResult(_ descriptor: FallbackDescriptor) -> FallbackResult? {
        guard descriptor.providerPaneCount == 1 else { return nil }
        guard let history = CodingAgentRegistry.shared.agent(id: descriptor.providerID)?.historyOptions(
            projectPath: descriptor.paneProjectPath,
            query: "",
            limit: 1,
            env: ProcessInfo.processInfo.environment,
            fileManager: .default
        ).first
        else { return nil }
        return FallbackResult(
            paneID: descriptor.paneID,
            providerID: descriptor.providerID,
            sessionID: history.sessionID,
            title: history.title.isEmpty ? descriptor.paneTitle : history.title,
            projectID: descriptor.projectID,
            worktreeID: descriptor.worktreeID,
            worktreePath: history.projectPath ?? descriptor.worktreePath,
            areaID: descriptor.areaID,
            tabID: descriptor.tabID
        )
    }
}

import Foundation

struct WorkspaceSnapshot: Codable {
    let projectID: UUID
    let worktreeID: UUID?
    let worktreePath: String?
    let tabs: [WorkspaceTabSnapshot]
    let activeTabID: UUID?

    private enum CodingKeys: String, CodingKey {
        case projectID
        case worktreeID
        case worktreePath
        case tabs
        case activeTabID
        case focusedAreaID
        case root
    }

    init(projectID: UUID, worktreeID: UUID?, worktreePath: String?, tabs: [WorkspaceTabSnapshot], activeTabID: UUID?) {
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.worktreePath = worktreePath
        self.tabs = tabs
        self.activeTabID = activeTabID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        worktreeID = try container.decodeIfPresent(UUID.self, forKey: .worktreeID)
        worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)

        if let tabs = try container.decodeIfPresent([WorkspaceTabSnapshot].self, forKey: .tabs) {
            self.tabs = tabs
            activeTabID = try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
            return
        }

        let focusedAreaID = try container.decodeIfPresent(UUID.self, forKey: .focusedAreaID)
        let root = try container.decode(SplitNodeSnapshot.self, forKey: .root)
        tabs = WorkspaceRestorer.upgradeLegacyTabs(root: root, focusedAreaID: focusedAreaID)
        activeTabID = tabs.first?.id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectID, forKey: .projectID)
        try container.encodeIfPresent(worktreeID, forKey: .worktreeID)
        try container.encodeIfPresent(worktreePath, forKey: .worktreePath)
        try container.encode(tabs, forKey: .tabs)
        try container.encodeIfPresent(activeTabID, forKey: .activeTabID)
    }
}

struct WorkspaceTabSnapshot: Codable {
    let id: UUID
    let customTitle: String?
    let colorID: String?
    let isPinned: Bool
    let focusedAreaID: UUID
    let root: SplitNodeSnapshot
}

indirect enum SplitNodeSnapshot: Codable {
    case tabArea(TabAreaSnapshot)
    case split(SplitBranchSnapshot)

    private enum CodingKeys: String, CodingKey {
        case type
        case tabArea
        case split
    }

    private enum NodeType: String, Codable {
        case tabArea
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
        case .tabArea:
            self = try .tabArea(container.decode(TabAreaSnapshot.self, forKey: .tabArea))
        case .split:
            self = try .split(container.decode(SplitBranchSnapshot.self, forKey: .split))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .tabArea(area):
            try container.encode(NodeType.tabArea, forKey: .type)
            try container.encode(area, forKey: .tabArea)
        case let .split(branch):
            try container.encode(NodeType.split, forKey: .type)
            try container.encode(branch, forKey: .split)
        }
    }
}

struct SplitBranchSnapshot: Codable {
    let direction: SplitDirectionSnapshot
    let ratio: Double
    let first: SplitNodeSnapshot
    let second: SplitNodeSnapshot
}

enum SplitDirectionSnapshot: String, Codable {
    case horizontal
    case vertical
}

struct TabAreaSnapshot: Codable {
    let id: UUID
    let projectPath: String
    let tabs: [TerminalTabSnapshot]
    let activeTabIndex: Int?
}

struct TerminalTabSnapshot: Codable {
    let kind: TerminalTab.Kind
    let customTitle: String?
    let colorID: String?
    let isPinned: Bool
    let projectPath: String
    let paneTitle: String
    let filePath: String?

    init(
        kind: TerminalTab.Kind,
        customTitle: String?,
        colorID: String?,
        isPinned: Bool,
        projectPath: String,
        paneTitle: String?,
        filePath: String? = nil
    ) {
        self.kind = kind
        self.customTitle = customTitle
        self.colorID = colorID
        self.isPinned = isPinned
        self.projectPath = projectPath
        self.paneTitle = paneTitle ?? "Terminal"
        self.filePath = filePath
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case customTitle
        case colorID
        case isPinned
        case projectPath
        case paneTitle
        case filePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(TerminalTab.Kind.self, forKey: .kind) ?? .terminal
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        colorID = try container.decodeIfPresent(String.self, forKey: .colorID)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        paneTitle = try container.decodeIfPresent(String.self, forKey: .paneTitle) ?? "Terminal"
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
    }
}

struct RestoredWorkspace {
    let key: WorktreeKey
    let workspace: WorktreeWorkspace
}

@MainActor
enum WorkspaceRestorer {
    static func restoreAll(
        from snapshots: [WorkspaceSnapshot],
        projects: [Project],
        worktrees: [UUID: [Worktree]]
    ) -> [RestoredWorkspace] {
        let projectByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var results: [RestoredWorkspace] = []

        for snapshot in snapshots {
            guard projectByID[snapshot.projectID] != nil else { continue }
            let worktreeList = worktrees[snapshot.projectID] ?? []
            guard let targetWorktree = resolveWorktree(for: snapshot, in: worktreeList) else { continue }

            let restoredTabs = snapshot.tabs.compactMap(restoreWorkspaceTab(from:))
            guard !restoredTabs.isEmpty else { continue }

            let workspace = WorktreeWorkspace(
                tabs: restoredTabs,
                activeTabID: snapshot.activeTabID ?? restoredTabs.first?.id
            )
            results.append(RestoredWorkspace(
                key: WorktreeKey(projectID: snapshot.projectID, worktreeID: targetWorktree.id),
                workspace: workspace
            ))
        }

        return results
    }

    static func snapshotAll(workspaces: [WorktreeKey: WorktreeWorkspace]) -> [WorkspaceSnapshot] {
        workspaces.map { key, workspace in
            WorkspaceSnapshot(
                projectID: key.projectID,
                worktreeID: key.worktreeID,
                worktreePath: workspace.tabs.first?.projectPath,
                tabs: workspace.tabs.map(snapshotWorkspaceTab),
                activeTabID: workspace.activeTabID
            )
        }
    }

    nonisolated static func upgradeLegacyTabs(root: SplitNodeSnapshot, focusedAreaID: UUID?) -> [WorkspaceTabSnapshot] {
        let visibleRoot = visibleLegacyRoot(root)
        let visibleFocusedAreaID = resolveFocusedAreaID(in: visibleRoot, requested: focusedAreaID)
        var tabs = [
            WorkspaceTabSnapshot(
                id: UUID(),
                customTitle: nil,
                colorID: nil,
                isPinned: false,
                focusedAreaID: visibleFocusedAreaID,
                root: visibleRoot
            ),
        ]

        for content in hiddenLegacyTabs(root) {
            let areaID = UUID()
            tabs.append(WorkspaceTabSnapshot(
                id: UUID(),
                customTitle: content.customTitle,
                colorID: content.colorID,
                isPinned: content.isPinned,
                focusedAreaID: areaID,
                root: .tabArea(TabAreaSnapshot(
                    id: areaID,
                    projectPath: content.projectPath,
                    tabs: [content],
                    activeTabIndex: 0
                ))
            ))
        }

        return tabs
    }

    private static func resolveWorktree(for snapshot: WorkspaceSnapshot, in worktrees: [Worktree]) -> Worktree? {
        if let worktreeID = snapshot.worktreeID,
           let match = worktrees.first(where: { $0.id == worktreeID })
        {
            return match
        }
        if let worktreePath = snapshot.worktreePath,
           let match = worktrees.first(where: { $0.path == worktreePath })
        {
            return match
        }
        return worktrees.first(where: { $0.isPrimary }) ?? worktrees.first
    }

    private static func restoreWorkspaceTab(from snapshot: WorkspaceTabSnapshot) -> WorkspaceTab? {
        let root = restoreSplitNode(from: snapshot.root)
        guard root.findArea(id: snapshot.focusedAreaID) != nil || !root.allAreas().isEmpty else { return nil }
        let focusedAreaID = root.findArea(id: snapshot.focusedAreaID)?.id ?? root.allAreas()[0].id
        return WorkspaceTab(
            id: snapshot.id,
            customTitle: snapshot.customTitle,
            colorID: snapshot.colorID,
            isPinned: snapshot.isPinned,
            root: root,
            focusedAreaID: focusedAreaID
        )
    }

    private static func restoreSplitNode(from snapshot: SplitNodeSnapshot) -> SplitNode {
        switch snapshot {
        case let .tabArea(areaSnapshot):
            return .tabArea(TabArea(restoring: areaSnapshot))
        case let .split(branchSnapshot):
            let first = restoreSplitNode(from: branchSnapshot.first)
            let second = restoreSplitNode(from: branchSnapshot.second)
            let direction: SplitDirection = branchSnapshot.direction == .horizontal ? .horizontal : .vertical
            return .split(SplitBranch(
                direction: direction,
                ratio: CGFloat(branchSnapshot.ratio),
                first: first,
                second: second
            ))
        }
    }

    private static func snapshotWorkspaceTab(_ tab: WorkspaceTab) -> WorkspaceTabSnapshot {
        WorkspaceTabSnapshot(
            id: tab.id,
            customTitle: tab.customTitle,
            colorID: tab.colorID,
            isPinned: tab.isPinned,
            focusedAreaID: tab.focusedAreaID,
            root: snapshotSplitNode(tab.root)
        )
    }

    private static func snapshotSplitNode(_ node: SplitNode) -> SplitNodeSnapshot {
        switch node {
        case let .tabArea(area):
            return .tabArea(area.snapshot())
        case let .split(branch):
            let direction: SplitDirectionSnapshot = branch.direction == .horizontal ? .horizontal : .vertical
            return .split(SplitBranchSnapshot(
                direction: direction,
                ratio: Double(branch.ratio),
                first: snapshotSplitNode(branch.first),
                second: snapshotSplitNode(branch.second)
            ))
        }
    }

    nonisolated private static func visibleLegacyRoot(_ root: SplitNodeSnapshot) -> SplitNodeSnapshot {
        switch root {
        case let .tabArea(area):
            let index = max(0, min(area.activeTabIndex ?? 0, max(area.tabs.count - 1, 0)))
            let tab = area.tabs.isEmpty ? TerminalTabSnapshot(
                kind: .terminal,
                customTitle: nil,
                colorID: nil,
                isPinned: false,
                projectPath: area.projectPath,
                paneTitle: "Terminal"
            ) : area.tabs[index]
            return .tabArea(TabAreaSnapshot(
                id: area.id,
                projectPath: area.projectPath,
                tabs: [tab],
                activeTabIndex: 0
            ))
        case let .split(branch):
            return .split(SplitBranchSnapshot(
                direction: branch.direction,
                ratio: branch.ratio,
                first: visibleLegacyRoot(branch.first),
                second: visibleLegacyRoot(branch.second)
            ))
        }
    }

    nonisolated private static func hiddenLegacyTabs(_ root: SplitNodeSnapshot) -> [TerminalTabSnapshot] {
        switch root {
        case let .tabArea(area):
            guard !area.tabs.isEmpty else { return [] }
            let activeIndex = max(0, min(area.activeTabIndex ?? 0, area.tabs.count - 1))
            return area.tabs.enumerated().compactMap { index, tab in
                index == activeIndex ? nil : tab
            }
        case let .split(branch):
            return hiddenLegacyTabs(branch.first) + hiddenLegacyTabs(branch.second)
        }
    }

    nonisolated private static func resolveFocusedAreaID(in root: SplitNodeSnapshot, requested: UUID?) -> UUID {
        let areaIDs = collectAreaIDs(in: root)
        if let requested, areaIDs.contains(requested) {
            return requested
        }
        return areaIDs.first ?? UUID()
    }

    nonisolated private static func collectAreaIDs(in root: SplitNodeSnapshot) -> [UUID] {
        switch root {
        case let .tabArea(area):
            [area.id]
        case let .split(branch):
            collectAreaIDs(in: branch.first) + collectAreaIDs(in: branch.second)
        }
    }
}

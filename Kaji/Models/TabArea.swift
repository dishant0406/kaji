import Foundation

@MainActor
@Observable
final class TabArea: Identifiable {
    let id: UUID
    let projectPath: String
    var tabs: [TerminalTab] = []
    var activeTabID: UUID?
    @ObservationIgnored private var contentIndex = TabAreaContentIndex()
    private var tabHistory: [UUID] = []

    init(projectPath: String) {
        id = UUID()
        self.projectPath = projectPath
        let tab = TerminalTab(pane: TerminalPaneState(projectPath: projectPath))
        tabs.append(tab)
        contentIndex.register(tab)
        activeTabID = tab.id
    }

    init(projectPath: String, existingTab tab: TerminalTab) {
        id = UUID()
        self.projectPath = projectPath
        tabs.append(tab)
        contentIndex.register(tab)
        activeTabID = tab.id
    }

    init(restoring snapshot: TabAreaSnapshot, projectID: UUID? = nil, worktreeID: UUID? = nil) {
        id = snapshot.id
        projectPath = snapshot.projectPath
        tabs = snapshot.tabs.map { TerminalTab(restoring: $0, projectID: projectID, worktreeID: worktreeID) }
        contentIndex = TabAreaContentIndex(tabs: tabs)
        if let index = snapshot.activeTabIndex, index >= 0, index < tabs.count {
            activeTabID = tabs[index].id
        } else {
            activeTabID = tabs.first?.id
        }
    }

    func snapshot() -> TabAreaSnapshot {
        let persistedTabs = tabs.filter { $0.kind != .diffViewer && $0.kind != .problems && $0.kind != .codeGraph && $0.kind != .browser }
        let activeIndex = persistedTabs.firstIndex(where: { $0.id == activeTabID })
        return TabAreaSnapshot(
            id: id,
            projectPath: projectPath,
            tabs: persistedTabs.map { $0.snapshot() },
            activeTabIndex: activeIndex
        )
    }

    var activeTab: TerminalTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    var mountedTabs: [TerminalTab] {
        let activeTabID = activeTabID
        let recency = Dictionary(uniqueKeysWithValues: tabHistory.enumerated().map { index, tabID in
            (tabID, index)
        })
        let snapshots = tabs.map { tab in
            TabContentMountSnapshot(
                tabID: tab.id,
                kind: tab.kind,
                isActive: tab.id == activeTabID,
                isModified: tab.content.editorState?.isModified ?? false,
                retainedUTF16Length: tab.content.editorState?.backingStore?.utf16Length,
                recencyRank: recency[tab.id] ?? -1
            )
        }
        let mountedIDs = TabContentMountPolicy.mountedTabIDs(snapshots: snapshots)
        return tabs.filter { mountedIDs.contains($0.id) }
    }

    var mountedNonEditorTabs: [TerminalTab] {
        mountedTabs.filter { $0.kind != .editor }
    }

    var hostedEditorTab: TerminalTab? {
        if activeTab?.kind == .editor {
            return activeTab
        }
        let editorTabs = tabs.filter { $0.kind == .editor }
        guard !editorTabs.isEmpty else { return nil }
        for tabID in tabHistory.reversed() {
            guard let tab = editorTabs.first(where: { $0.id == tabID }) else { continue }
            return tab
        }
        return editorTabs.first
    }

    func existingFileTabID(filePath: String) -> UUID? {
        contentIndex.editorTabID(filePath: filePath)
            ?? contentIndex.filePreviewTabID(filePath: filePath)
    }

    func existingDiffViewerTabID(filePath: String, isStaged: Bool) -> UUID? {
        contentIndex.diffViewerTabID(filePath: filePath, isStaged: isStaged)
    }

    private var firstUnpinnedIndex: Int {
        tabs.firstIndex(where: { !$0.isPinned }) ?? tabs.count
    }

    private var tabIDs: Set<UUID> {
        Set(tabs.map(\.id))
    }

    func createTab() {
        insertTab(TerminalTab(pane: TerminalPaneState(projectPath: projectPath)))
    }

    func createTab(inDirectory directory: String) {
        insertTab(TerminalTab(pane: TerminalPaneState(projectPath: directory)))
    }

    func createVCSTab() {
        insertTab(TerminalTab(vcsState: VCSTabState(projectPath: projectPath)))
    }

    func createCodeGraphTab(projectID: UUID, worktreeID: UUID, graphURL: URL) {
        insertTab(TerminalTab(codeGraphState: KajiCodeGraphTabState(
            projectID: projectID,
            worktreeID: worktreeID,
            projectPath: projectPath,
            graphURL: graphURL
        )))
    }

    func createBrowserTab(url: String = "https://www.google.com") {
        if let existingTabID = contentIndex.existingBrowserTabID() {
            selectTab(existingTabID)
            return
        }
        insertTab(TerminalTab(browserState: BrowserPaneState(projectPath: projectPath, url: url)))
    }

    func createCommandTab(title: String, command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insertTab(TerminalTab(pane: TerminalPaneState(
            projectPath: projectPath,
            title: title,
            injectedCommand: trimmed
        )))
    }

    func createEditorTab(filePath: String) {
        if let existingTabID = contentIndex.editorTabID(filePath: filePath) {
            selectTab(existingTabID)
            return
        }
        insertTab(TerminalTab(editorState: EditorTabState(projectPath: projectPath, filePath: filePath)))
    }

    func createFilePreviewTab(filePath: String, kind: FilePreviewKind) {
        if let existingTabID = contentIndex.filePreviewTabID(filePath: filePath) {
            selectTab(existingTabID)
            return
        }
        insertTab(TerminalTab(filePreviewState: FilePreviewTabState(projectPath: projectPath, filePath: filePath, kind: kind)))
    }

    func createDiffViewerTab(vcs: VCSTabState, filePath: String, isStaged: Bool) {
        if let existingTabID = contentIndex.diffViewerTabID(filePath: filePath, isStaged: isStaged) {
            selectTab(existingTabID)
            return
        }
        insertTab(TerminalTab(diffViewerState: DiffViewerTabState(
            vcs: vcs,
            filePath: filePath,
            isStaged: isStaged
        )))
    }

    func createExternalEditorTab(filePath: String, command: String) {
        if let existingTabID = contentIndex.externalEditorTabID(filePath: filePath) {
            selectTab(existingTabID)
            return
        }
        let title = "\(Self.commandTitle(command)) \(URL(fileURLWithPath: filePath).lastPathComponent)"
        let pane = TerminalPaneState(
            projectPath: projectPath,
            title: title,
            startupCommand: Self.editorLaunchCommand(command: command, filePath: filePath),
            externalEditorFilePath: filePath
        )
        insertTab(TerminalTab(pane: pane))
    }

    static func editorLaunchCommand(command: String, filePath: String) -> String {
        if command.contains("{file}") {
            return command.replacingOccurrences(of: "{file}", with: filePath)
        }
        return command + " " + shellEscapedPath(filePath)
    }

    static func commandTitle(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return "Editor" }
        return String(first)
    }

    private static func shellEscapedPath(_ path: String) -> String {
        let needsQuoting = path.contains { character in
            character.isWhitespace || "'\"\\&|;$`!()[]{}<>*?".contains(character)
        }
        guard needsQuoting else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func insertTab(_ tab: TerminalTab) {
        tabs.append(tab)
        contentIndex.register(tab)
        activate(tab.id)
    }

    enum InsertSide { case left, right }

    func createTabAdjacent(to tabID: UUID, side: InsertSide) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = TerminalTab(pane: TerminalPaneState(projectPath: projectPath))
        let desiredIndex = side == .left ? index : index + 1
        let insertIndex = max(desiredIndex, firstUnpinnedIndex)
        tabs.insert(tab, at: insertIndex)
        contentIndex.register(tab)
        activate(tab.id)
    }

    func closeTab(_ tabID: UUID) -> UUID? {
        guard let tab = removeTab(tabID) else { return nil }
        return tab.content.pane?.id
    }

    func selectTab(_ tabID: UUID) {
        guard activeTabID != tabID else { return }
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        activate(tabID)
    }

    func selectTabByIndex(_ index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectTab(tabs[index].id)
    }

    func selectNextTab() {
        guard tabs.count > 1, let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID })
        else { return }
        let next = (index + 1) % tabs.count
        selectTab(tabs[next].id)
    }

    func selectPreviousTab() {
        guard tabs.count > 1, let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID })
        else { return }
        let previous = (index - 1 + tabs.count) % tabs.count
        selectTab(tabs[previous].id)
    }

    func reorderTab(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard source.count == 1, let sourceIndex = source.first else { return }
        let constrainedDestination = PinnedReorderPolicy.constrainedDestination(
            sourceIndex: sourceIndex,
            destination: destination,
            items: tabs,
            isPinned: { $0.isPinned }
        )
        tabs.move(fromOffsets: source, toOffset: constrainedDestination)
    }

    func removeTab(_ tabID: UUID) -> TerminalTab? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let tab = tabs[index]
        guard !tab.isPinned else { return nil }
        tabs.remove(at: index)
        contentIndex.unregister(tab)
        let existingTabIDs = tabIDs
        tabHistory = TabHistoryPolicy.compacted(
            tabHistory,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs
        )
        guard activeTabID == tabID else { return tab }
        if let previousTabID = TabHistoryPolicy.previousTabID(
            in: tabHistory,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs
        ) {
            activeTabID = previousTabID
            tabHistory = TabHistoryPolicy.compacted(
                tabHistory,
                activeTabID: activeTabID,
                existingTabIDs: existingTabIDs
            )
            return tab
        }
        activeTabID = tabs.last?.id
        tabHistory = TabHistoryPolicy.compacted(
            tabHistory,
            activeTabID: activeTabID,
            existingTabIDs: existingTabIDs
        )
        return tab
    }

    func insertExistingTab(_ tab: TerminalTab) {
        let insertIndex = tab.isPinned ? firstUnpinnedIndex : tabs.count
        tabs.insert(tab, at: insertIndex)
        contentIndex.register(tab)
        activate(tab.id)
    }

    func setCustomTitle(_ tabID: UUID, title: String?) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.customTitle = title
    }

    func setColorID(_ tabID: UUID, colorID: String?) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.colorID = colorID
    }

    func togglePin(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabs[index]
        tab.isPinned.toggle()
        tabs.remove(at: index)
        if tab.isPinned {
            tabs.insert(tab, at: firstUnpinnedIndex)
        } else {
            let insertIndex = max(firstUnpinnedIndex, 0)
            tabs.insert(tab, at: insertIndex)
        }
    }

    private func activate(_ tabID: UUID) {
        tabHistory = TabHistoryPolicy.recordingVisit(
            from: activeTabID,
            to: tabID,
            in: tabHistory,
            existingTabIDs: tabIDs
        )
        activeTabID = tabID
        pruneInactiveEditorResources()
    }

    private func pruneInactiveEditorResources() {
        let activeTabID = activeTabID
        let recency = Dictionary(uniqueKeysWithValues: tabHistory.enumerated().map { index, tabID in
            (tabID, index)
        })
        let snapshots = tabs.compactMap { tab -> EditorInactiveResourceSnapshot? in
            guard let state = tab.content.editorState else { return nil }
            return EditorInactiveResourceSnapshot(
                tabID: tab.id,
                isActive: tab.id == activeTabID,
                isModified: state.isModified,
                isLoading: state.isLoading,
                isIncrementalLoading: state.isIncrementalLoading,
                retainedUTF16Length: state.backingStore?.utf16Length,
                recencyRank: recency[tab.id] ?? -1
            )
        }
        let releaseIDs = EditorInactiveResourceBudgetPolicy.tabIDsToRelease(snapshots: snapshots)
        guard !releaseIDs.isEmpty else { return }
        for tab in tabs where releaseIDs.contains(tab.id) {
            tab.content.editorState?.releaseInactiveResourcesForBudget()
        }
    }
}

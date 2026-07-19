import AppKit
import Reorderable
import SwiftUI

enum SidebarLayout {
    static let collapsedWidth: CGFloat = 52
    static let expandedWidth: CGFloat = 248
    static let width: CGFloat = collapsedWidth

    static func resolvedWidth(expanded: Bool) -> CGFloat {
        expanded ? expandedWidth : collapsedWidth
    }
}

struct Sidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReordering = false
    @State private var expanded = UserDefaults.standard.bool(forKey: "kaji.sidebarExpanded")

    var body: some View {
        VStack(spacing: 0) {
            projectList
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

            SidebarFooter(expanded: expanded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .frame(width: SidebarLayout.resolvedWidth(expanded: expanded))
        .background(SidebarBackgroundSurface())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
        .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: expanded)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleExpanded()
        }
    }

    private func toggleExpanded() {
        withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
            expanded.toggle()
        }
        UserDefaults.standard.set(expanded, forKey: "kaji.sidebarExpanded")
    }

    private var addButton: some View {
        SidebarAddProjectButton(expanded: expanded) {
            ProjectOpenService.openProject(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        }
        .help(shortcutTooltip("Add Project", for: .openProject))
    }

    private var projectList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: expanded ? 4 : 6) {
                ReorderableVStack(
                    projectStore.projects,
                    onMove: { source, destination in
                        projectStore.reorder(
                            fromOffsets: IndexSet(integer: source),
                            toOffset: ReorderMoveDestination.arrayMoveOffset(from: source, to: destination)
                        )
                    },
                    onDragStateChange: { dragging in
                        isReordering = dragging
                    },
                    content: { project, isDragged in
                        projectRow(project, isDragged: isDragged)
                    }
                )
                addButton
            }
            .padding(.horizontal, expanded ? 10 : 8)
            .padding(.vertical, 6)
        }
        .autoScrollOnEdges()
        .coordinateSpace(name: "sidebar")
    }

    @ViewBuilder
    private func projectRow(_ project: Project, isDragged: Bool) -> some View {
        let index = projectStore.projects.firstIndex(where: { $0.id == project.id }) ?? 0
        Group {
            if expanded {
                ExpandedProjectRow(
                    project: project,
                    shortcutIndex: index < 9 ? index + 1 : nil,
                    isAnyDragging: isReordering,
                    onSelect: { select(project) },
                    onRemove: { remove(project) },
                    onRename: { projectStore.rename(id: project.id, to: $0) },
                    onSetLogo: { projectStore.setLogo(id: project.id, to: $0) },
                    onSetIconColor: { projectStore.setIconColor(id: project.id, to: $0) }
                )
            } else {
                ProjectRow(
                    project: project,
                    shortcutIndex: index < 9 ? index + 1 : nil,
                    isAnyDragging: isReordering,
                    onSelect: { select(project) },
                    onRemove: { remove(project) },
                    onRename: { projectStore.rename(id: project.id, to: $0) },
                    onSetLogo: { projectStore.setLogo(id: project.id, to: $0) },
                    onSetIconColor: { projectStore.setIconColor(id: project.id, to: $0) }
                )
            }
        }
        .transition(KajiMotion.contentSwitchTransition(reduceMotion: reduceMotion))
        .opacity(isDragged ? 0.92 : 1)
        .padding(.bottom, expanded ? 4 : 6)
    }

    private func shortcutTooltip(_ name: String, for action: ShortcutAction) -> String {
        "\(name) (\(KeyBindingStore.shared.combo(for: action).displayString))"
    }

    private func select(_ project: Project) {
        worktreeStore.ensurePrimary(for: project)
        guard let worktree = worktreeStore.preferred(
            for: project.id,
            matching: appState.activeWorktreeID[project.id]
        )
        else { return }
        appState.selectProject(project, worktree: worktree)
    }

    private func remove(_ project: Project) {
        let impact = ProjectRemovalCoordinator.impact(project: project, appState: appState, worktreeStore: worktreeStore)
        presentRemoveConfirmation(project: project, impact: impact) {
            Task { @MainActor in
                _ = await ProjectRemovalService.shared.removeManually(
                    project: project,
                    appState: appState,
                    projectStore: projectStore,
                    worktreeStore: worktreeStore
                )
            }
        }
    }

    private func presentRemoveConfirmation(project: Project, impact: ProjectRemovalImpact, onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Remove project \"\(project.name)\" from Kaji?"
        alert.informativeText = removeConfirmationMessage(impact: impact)
        alert.alertStyle = impact.hasRunningWork || impact.hasUnsavedEditors ? .warning : .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            if alert.runModal() == .alertFirstButtonReturn {
                onConfirm()
            }
            return
        }

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            onConfirm()
        }
    }

    private func removeConfirmationMessage(impact: ProjectRemovalImpact) -> String {
        var lines = ["This removes Kaji workspace state for this project. The project folder is not deleted."]
        if impact.worktreeCount > 1 {
            lines.append("Kaji-managed worktrees for this project will be cleaned up.")
        }
        if impact.hasUnsavedEditors {
            lines.append("Unsaved editor changes in this project will be discarded.")
        }
        if impact.hasRunningTerminals {
            lines.append("Running terminal processes in this project will be stopped.")
        }
        if impact.hasRunningAgents || impact.hasCodeGraphSessions {
            lines.append("Running agent work for this project will be stopped and marked stale.")
        }
        return lines.joined(separator: "\n\n")
    }
}

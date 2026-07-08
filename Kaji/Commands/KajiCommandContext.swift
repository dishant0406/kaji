import AppKit

@MainActor
struct KajiCommandContext {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let keyBindings: KeyBindingStore
    let config: KajiConfig
    let termy: TermyService
    let updateService: UpdateService

    var isMainWindowFocused: Bool {
        ShortcutContext.isMainWindow(NSApp.keyWindow)
    }

    var terminalPasteboardCommands: TerminalPasteboardCommandRouter {
        TerminalPasteboardCommandRouter.focusedTerminal(appState: appState)
    }

    func performShortcutAction(_ action: ShortcutAction) {
        _ = shortcutDispatcher.perform(action, activeProject: activeProject) { project in
            NotificationCenter.default.post(name: .toggleAttachedVCS, object: project.id)
        }
    }

    private var activeProject: Project? {
        guard let projectID = appState.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == projectID }
    }

    private var shortcutDispatcher: ShortcutActionDispatcher {
        ShortcutActionDispatcher(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            termy: termy
        )
    }
}

import SwiftUI

@MainActor
struct KajiCommands: Commands {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let keyBindings: KeyBindingStore
    let config: KajiConfig
    let termy: TermyService
    let updateService: UpdateService

    private var context: KajiCommandContext {
        KajiCommandContext(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            keyBindings: keyBindings,
            config: config,
            termy: termy,
            updateService: updateService
        )
    }

    var body: some Commands {
        KajiAppMenuCommands(context: context)
        KajiEditCommands(context: context)
        KajiWorkspaceCommands(context: context)
        KajiWindowNavigationCommands(context: context)
        KajiSidebarNavigationCommands(context: context)
    }
}

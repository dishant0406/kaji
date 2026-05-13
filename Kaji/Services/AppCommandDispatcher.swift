import Foundation

@MainActor
struct AppCommandDispatcher {
    let shortcutDispatcher: ShortcutActionDispatcher
    let activeProject: Project?
    let openVCS: (Project) -> Void

    func perform(_ command: AppCommand) -> Bool {
        shortcutDispatcher.perform(command.id, activeProject: activeProject, openVCS: openVCS)
    }
}

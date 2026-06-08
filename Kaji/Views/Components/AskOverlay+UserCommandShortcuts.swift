import Foundation

extension AskOverlay {
    func runUserCommandShortcut(_ shortcut: UserCommandShortcut) {
        guard let worktree = selectedWorktree else {
            nativeCommandRunner.showMessage(
                title: "::\(shortcut.slug)",
                message: "Select a project worktree before running this command shortcut.",
                workingDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
            return
        }
        guard let state = UserCommandShortcutParser.state(for: fieldText) else { return }
        let workingDirectory = URL(fileURLWithPath: worktree.path)
        Task { @MainActor in
            let result = await UserCommandShortcutResolver.resolve(
                shortcut: shortcut,
                state: state,
                workingDirectory: workingDirectory
            )
            switch result {
            case let .plan(plan):
                nativeCommandRunner.run(plan)
            case let .failure(title, message):
                nativeCommandRunner.showMessage(title: title, message: message, workingDirectory: workingDirectory)
            }
        }
    }
}

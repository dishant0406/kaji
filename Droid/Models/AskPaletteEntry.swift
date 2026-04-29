import Foundation

enum AskPaletteAction: Hashable {
    case command(AskSlashCommand)
    case project(Project)
    case worktree(Worktree)
    case provider(AskProvider)
    case sessionMode(AskSessionMode)
    case session(AskSessionOption)
    case submit
}

struct AskPaletteEntry: Identifiable, Hashable {
    let action: AskPaletteAction
    let title: String
    let detail: String
    let annotation: String?

    var id: String {
        switch action {
        case .command(let command):
            "command:\(command.rawValue)"
        case .project(let project):
            "project:\(project.id.uuidString)"
        case .worktree(let worktree):
            "worktree:\(worktree.id.uuidString)"
        case .provider(let provider):
            "provider:\(provider.rawValue)"
        case .sessionMode(let mode):
            "session-mode:\(mode.rawValue)"
        case .session(let session):
            "session:\(session.id.uuidString)"
        case .submit:
            "submit"
        }
    }
}

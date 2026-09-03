import Foundation

extension TerminalTab.Kind {
    var keepsMountedWhenInactive: Bool {
        switch self {
        case .terminal,
             .browser:
            true
        case .vcs,
             .editor,
             .filePreview,
             .diffViewer,
             .problems,
             .parentAgent:
            false
        }
    }
}

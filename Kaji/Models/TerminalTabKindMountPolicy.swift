import Foundation

extension TerminalTab.Kind {
    var keepsMountedWhenInactive: Bool {
        switch self {
        case .terminal,
             .browser,
             .parentAgent:
            true
        case .vcs,
             .editor,
             .filePreview,
             .diffViewer,
             .problems,
             .codeGraph:
            false
        }
    }
}

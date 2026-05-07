import Foundation

extension ParentAgentTaskStatus {
    var isTerminal: Bool {
        switch self {
        case .completed,
             .failed,
             .cancelled,
             .stale:
            true
        case .planning,
             .running,
             .waitingForUser:
            false
        }
    }
}

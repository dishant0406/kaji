import Foundation

enum DroidCodeGraphInstallPhase: String, Codable {
    case notInstalled
    case installed
    case failed
}

struct DroidCodeGraphExtensionState: Codable, Equatable {
    var isEnabled: Bool
    var phase: DroidCodeGraphInstallPhase
    var graphifyCommit: String?
    var installedAt: Date?
    var message: String?

    static let initial = Self(
        isEnabled: false,
        phase: .notInstalled,
        graphifyCommit: nil,
        installedAt: nil,
        message: nil
    )
}

struct DroidCodeGraphStatus: Codable, Equatable {
    let ok: Bool
    let mode: String
    let nodes: Int
    let edges: Int
    let communities: Int
    let graphPath: String
    let droidGraphPath: String
    let reportPath: String
    let message: String?
}

struct DroidCodeGraphRunRequest: Equatable {
    let projectID: UUID
    let worktreeID: UUID
    let projectPath: String
    let mode: String
}

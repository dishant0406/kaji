import Foundation

enum KajiCodeGraphInstallPhase: String, Codable {
    case notInstalled
    case installed
    case failed
}

struct KajiCodeGraphExtensionState: Codable, Equatable {
    var isEnabled: Bool
    var phase: KajiCodeGraphInstallPhase
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

struct KajiCodeGraphStatus: Codable, Equatable {
    let ok: Bool
    let mode: String
    let nodes: Int
    let edges: Int
    let communities: Int
    let graphPath: String
    let kajiGraphPath: String
    let reportPath: String
    let buildID: String?
    let state: String?
    let message: String?
}

struct KajiCodeGraphRunRequest: Equatable {
    let projectID: UUID
    let worktreeID: UUID
    let projectPath: String
    let mode: String
}

import Foundation

struct CodingAgentSessionMetadata: Codable, Hashable {
    let providerID: String
    let paneID: UUID
    let sessionID: String
    let transcriptPath: String?
    let title: String?
    let cwd: String?
    let source: String?
    let updatedAt: Date
}

struct CodingAgentSessionSeed: Hashable {
    let providerID: String
    let sessionID: String
    let title: String?
    let transcriptPath: String?
    let cwd: String?
}

struct CodingAgentSessionEventBody: Codable, Hashable {
    let sessionID: String
    var transcriptPath: String?
    var title: String?
    var cwd: String?
    var source: String?
    var projectID: UUID?
    var worktreeID: UUID?
    var worktreePath: String?

    var isValid: Bool {
        !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func decode(_ body: String) -> Self? {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              decoded.isValid
        else { return nil }
        return decoded
    }
}

import Foundation

enum ChildAgentFeedEntryKind: String, Codable, Hashable {
    case status
    case transcript
    case terminal
    case final
}

struct ChildAgentFeedEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: ChildAgentFeedEntryKind
    let text: String
    let timestamp: Date

    init(kind: ChildAgentFeedEntryKind, text: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
    }
}

struct ChildAgentFeed: Identifiable, Codable, Hashable {
    let id: UUID
    var entries: [ChildAgentFeedEntry]
    var finalAnswer: String?
    var terminalOutput: String?
    var updatedAt: Date

    init(id: UUID) {
        self.id = id
        self.entries = []
        self.finalAnswer = nil
        self.terminalOutput = nil
        self.updatedAt = Date()
    }
}

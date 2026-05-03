import Foundation

enum ParentAgentTaskStatus: String, Codable {
    case planning
    case running
    case waitingForUser
    case completed
    case failed
    case cancelled
}

enum ParentAgentTimelineKind: String, Codable {
    case user
    case assistant
    case thinking
    case childRun
    case event
    case tool
    case final
    case error
}

struct ParentAgentTimelineItem: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: ParentAgentTimelineKind
    var title: String
    var detail: String
    var childRunID: UUID?
    var isComplete: Bool
    var createdAt: Date

    init(kind: ParentAgentTimelineKind, title: String, detail: String, childRunID: UUID? = nil, isComplete: Bool = true) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.detail = detail
        self.childRunID = childRunID
        self.isComplete = isComplete
        self.createdAt = Date()
    }
}

struct ParentAgentTask: Identifiable, Codable, Hashable {
    let id: UUID
    var prompt: String
    var status: ParentAgentTaskStatus
    var timeline: [ParentAgentTimelineItem]
    var childRunIDs: [UUID]
    var spawnFingerprints: [String]
    var pendingQuestion: String?
    var pendingQuestionToolID: String?
    var createdAt: Date
    var updatedAt: Date

    init(prompt: String) {
        self.id = UUID()
        self.prompt = prompt
        self.status = .planning
        self.timeline = [ParentAgentTimelineItem(kind: .user, title: "You", detail: prompt)]
        self.childRunIDs = []
        self.spawnFingerprints = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct ParentAgentProjectContext: Codable, Hashable {
    let id: String
    let name: String
    let path: String
}

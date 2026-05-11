import Foundation

enum ParentAgentTaskStatus: String, Codable {
    case planning
    case running
    case waitingForUser
    case completed
    case failed
    case cancelled
    case stale
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
    var attachments: [ParentAgentAttachmentContext]
    var childRunID: UUID?
    var isComplete: Bool
    var createdAt: Date

    init(
        kind: ParentAgentTimelineKind,
        title: String,
        detail: String,
        attachments: [ParentAgentAttachmentContext] = [],
        childRunID: UUID? = nil,
        isComplete: Bool = true
    ) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.detail = detail
        self.attachments = attachments
        self.childRunID = childRunID
        self.isComplete = isComplete
        self.createdAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case detail
        case attachments
        case childRunID
        case isComplete
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ParentAgentTimelineKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        attachments = try container.decodeIfPresent([ParentAgentAttachmentContext].self, forKey: .attachments) ?? []
        childRunID = try container.decodeIfPresent(UUID.self, forKey: .childRunID)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct ParentAgentTask: Identifiable, Codable, Hashable {
    let id: UUID
    var prompt: String
    var status: ParentAgentTaskStatus
    var timeline: [ParentAgentTimelineItem]
    var assignments: [ParentAgentAssignment]
    var childRunIDs: [UUID]
    var spawnFingerprints: [String]
    var pendingQuestion: String?
    var pendingQuestionToolID: String?
    var pendingQuestionOptions: [ParentAgentQuestionOption]
    var createdAt: Date
    var updatedAt: Date

    init(prompt: String, attachments: [ParentAgentAttachmentContext] = []) {
        self.id = UUID()
        self.prompt = prompt
        self.status = .planning
        self.timeline = [ParentAgentTimelineItem(kind: .user, title: "You", detail: prompt, attachments: attachments)]
        self.assignments = []
        self.childRunIDs = []
        self.spawnFingerprints = []
        self.pendingQuestionOptions = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case status
        case timeline
        case assignments
        case childRunIDs
        case spawnFingerprints
        case pendingQuestion
        case pendingQuestionToolID
        case pendingQuestionOptions
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        prompt = try container.decode(String.self, forKey: .prompt)
        status = try container.decode(ParentAgentTaskStatus.self, forKey: .status)
        timeline = try container.decode([ParentAgentTimelineItem].self, forKey: .timeline)
        assignments = try container.decodeIfPresent([ParentAgentAssignment].self, forKey: .assignments) ?? []
        childRunIDs = try container.decodeIfPresent([UUID].self, forKey: .childRunIDs) ?? []
        spawnFingerprints = try container.decodeIfPresent([String].self, forKey: .spawnFingerprints) ?? []
        pendingQuestion = try container.decodeIfPresent(String.self, forKey: .pendingQuestion)
        pendingQuestionToolID = try container.decodeIfPresent(String.self, forKey: .pendingQuestionToolID)
        pendingQuestionOptions = try container.decodeIfPresent([ParentAgentQuestionOption].self, forKey: .pendingQuestionOptions) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

struct ParentAgentQuestionOption: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let detail: String?
    let value: String
}

struct ParentAgentProjectContext: Codable, Hashable {
    let id: String
    let name: String
    let path: String
    let worktrees: [ParentAgentWorktreeContext]
    let activeWorktreeID: String?

    init(
        id: String,
        name: String,
        path: String,
        worktrees: [ParentAgentWorktreeContext] = [],
        activeWorktreeID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.worktrees = worktrees
        self.activeWorktreeID = activeWorktreeID
    }
}

struct ParentAgentWorktreeContext: Codable, Hashable {
    let id: String
    let name: String
    let path: String
    let branch: String?
    let isPrimary: Bool
}

import Foundation

enum WorktreeSource: String, Codable, Hashable {
    case kaji
    case external
}

enum WorktreeBackend: String, Codable, Hashable {
    case primary
    case rift
    case externalRift
}

struct Worktree: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var branch: String?
    var source: WorktreeSource
    var backend: WorktreeBackend
    var riftID: String?
    var isPrimary: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        branch: String? = nil,
        source: WorktreeSource = .kaji,
        backend: WorktreeBackend? = nil,
        riftID: String? = nil,
        isPrimary: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
        self.source = source
        self.backend = backend ?? Self.defaultBackend(isPrimary: isPrimary, source: source)
        self.riftID = riftID
        self.isPrimary = isPrimary
        self.createdAt = createdAt
    }

    var isExternallyManaged: Bool {
        !isPrimary && source == .external
    }

    var canBeRemoved: Bool {
        !isPrimary && !isExternallyManaged
    }

    private static func defaultBackend(isPrimary: Bool, source: WorktreeSource) -> WorktreeBackend {
        if isPrimary {
            return .primary
        }
        return source == .external ? .externalRift : .rift
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case branch
        case source
        case backend
        case riftID
        case isPrimary
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        source = try container.decodeIfPresent(WorktreeSource.self, forKey: .source) ?? .kaji
        isPrimary = try container.decode(Bool.self, forKey: .isPrimary)
        backend = try container.decodeIfPresent(WorktreeBackend.self, forKey: .backend)
            ?? Self.defaultBackend(isPrimary: isPrimary, source: source)
        riftID = try container.decodeIfPresent(String.self, forKey: .riftID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

import Foundation

struct DroidCodeGraphDocument: Codable, Equatable {
    let projectPath: String
    let builtAt: String
    let versionID: String?
    let versionBuiltAt: String?
    let git: DroidCodeGraphGitSnapshot?
    let nodes: [DroidCodeGraphNode]
    let edges: [DroidCodeGraphEdge]
    let communities: [DroidCodeGraphCommunity]

    init(
        projectPath: String,
        builtAt: String,
        versionID: String? = nil,
        versionBuiltAt: String? = nil,
        git: DroidCodeGraphGitSnapshot? = nil,
        nodes: [DroidCodeGraphNode],
        edges: [DroidCodeGraphEdge],
        communities: [DroidCodeGraphCommunity]
    ) {
        self.projectPath = projectPath
        self.builtAt = builtAt
        self.versionID = versionID
        self.versionBuiltAt = versionBuiltAt
        self.git = git
        self.nodes = nodes
        self.edges = edges
        self.communities = communities
    }

    var nodeByID: [String: DroidCodeGraphNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }
}

struct DroidCodeGraphNode: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let fileType: String
    let sourceFile: String?
    let community: Int?
    let degree: Int

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case fileType = "file_type"
        case sourceFile = "source_file"
        case community
        case degree
    }
}

struct DroidCodeGraphEdge: Codable, Equatable, Identifiable {
    let source: String
    let target: String
    let relation: String
    let confidence: String

    var id: String {
        "\(source)->\(target):\(relation)"
    }
}

struct DroidCodeGraphCommunity: Codable, Equatable, Identifiable {
    let id: Int
    let label: String
    let nodeCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case nodeCount = "node_count"
    }
}

enum DroidCodeGraphDocumentLoader {
    static func load(url: URL) throws -> DroidCodeGraphDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DroidCodeGraphDocument.self, from: data)
    }

    static func loadOffMain(url: URL) async throws -> DroidCodeGraphDocument {
        try await GitProcessRunner.offMainThrowing {
            try load(url: url)
        }
    }
}

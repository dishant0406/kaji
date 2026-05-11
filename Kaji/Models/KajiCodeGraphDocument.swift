import Foundation

struct KajiCodeGraphDocument: Codable, Equatable {
    let projectPath: String
    let builtAt: String
    let versionID: String?
    let versionBuiltAt: String?
    let git: KajiCodeGraphGitSnapshot?
    let nodes: [KajiCodeGraphNode]
    let edges: [KajiCodeGraphEdge]
    let communities: [KajiCodeGraphCommunity]

    init(
        projectPath: String,
        builtAt: String,
        versionID: String? = nil,
        versionBuiltAt: String? = nil,
        git: KajiCodeGraphGitSnapshot? = nil,
        nodes: [KajiCodeGraphNode],
        edges: [KajiCodeGraphEdge],
        communities: [KajiCodeGraphCommunity]
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

    var nodeByID: [String: KajiCodeGraphNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }
}

struct KajiCodeGraphNode: Codable, Equatable, Identifiable {
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

struct KajiCodeGraphEdge: Codable, Equatable, Identifiable {
    let source: String
    let target: String
    let relation: String
    let confidence: String

    var id: String {
        "\(source)->\(target):\(relation)"
    }
}

struct KajiCodeGraphCommunity: Codable, Equatable, Identifiable {
    let id: Int
    let label: String
    let nodeCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case nodeCount = "node_count"
    }
}

enum KajiCodeGraphDocumentLoader {
    static func load(url: URL) throws -> KajiCodeGraphDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(KajiCodeGraphDocument.self, from: data)
    }

    static func loadOffMain(url: URL) async throws -> KajiCodeGraphDocument {
        try await GitProcessRunner.offMainThrowing {
            try load(url: url)
        }
    }
}

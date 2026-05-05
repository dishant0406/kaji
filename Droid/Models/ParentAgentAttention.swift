import Foundation

enum ParentAgentAttentionKind: String, Codable, Hashable {
    case permission
    case question
    case blocked
    case idle
}

struct ParentAgentAttention: Codable, Hashable {
    let kind: ParentAgentAttentionKind
    let providerID: String
    let title: String
    let detail: String
    let suggestedAction: String
}

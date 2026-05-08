import Foundation

@MainActor
@Observable
final class CodingAgentSessionMetadataStore {
    static let shared = CodingAgentSessionMetadataStore()

    private(set) var sessionsByPaneID: [UUID: CodingAgentSessionMetadata] = [:]

    private init() {}

    func update(_ metadata: CodingAgentSessionMetadata) {
        sessionsByPaneID[metadata.paneID] = metadata
        AgentRunStore.shared.setSessionMetadata(metadata)
    }

    func metadata(paneID: UUID) -> CodingAgentSessionMetadata? {
        sessionsByPaneID[paneID]
    }

    func remove(paneID: UUID) {
        sessionsByPaneID.removeValue(forKey: paneID)
    }

    func reset() {
        sessionsByPaneID.removeAll()
    }
}

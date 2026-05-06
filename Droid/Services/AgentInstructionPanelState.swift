import Foundation

@MainActor
@Observable
final class AgentInstructionPanelState {
    var groups: [AgentInstructionGroup] = []
    var selectedAgentID: String?
    var selectedDocumentID: String?

    var selectedGroup: AgentInstructionGroup? {
        groups.first { $0.id == selectedAgentID } ?? groups.first
    }

    var selectedDocument: AgentInstructionDocument? {
        guard let group = selectedGroup else { return nil }
        return group.documents.first { $0.id == selectedDocumentID } ?? group.documents.first
    }

    func refresh(projectPath: String, enabledLaunchers: [CLILauncherConfiguration]) {
        let enabledIDs = Set(enabledLaunchers.map(\.id))
        let definitions = CodingAgentRegistry.shared.definitions.filter { enabledIDs.contains($0.id) }
        groups = AgentInstructionDiscovery.discover(projectPath: projectPath, definitions: definitions)
        normalizeSelection()
    }

    func selectAgent(_ id: String) {
        selectedAgentID = id
        selectedDocumentID = selectedGroup?.documents.first?.id
    }

    func selectDocument(_ id: String) {
        selectedDocumentID = id
    }

    private func normalizeSelection() {
        if !groups.contains(where: { $0.id == selectedAgentID }) {
            selectedAgentID = groups.first?.id
        }
        guard let group = selectedGroup else {
            selectedDocumentID = nil
            return
        }
        if !group.documents.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = group.documents.first?.id
        }
    }
}

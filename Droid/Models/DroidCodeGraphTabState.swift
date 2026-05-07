import Foundation

@MainActor
@Observable
final class DroidCodeGraphTabState {
    let projectID: UUID
    let worktreeID: UUID
    let projectPath: String
    let latestGraphURL: URL
    var activeGraphURL: URL
    var document: DroidCodeGraphDocument?
    var selectedNodeID: String?
    var query = ""
    var viewMode: DroidCodeGraphViewMode = .flow
    var errorMessage: String?
    var isLoading = false
    var versions: [DroidCodeGraphVersionEntry] = []
    var activeVersionID: String?

    init(projectID: UUID, worktreeID: UUID, projectPath: String, graphURL: URL) {
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.projectPath = projectPath
        self.latestGraphURL = graphURL
        self.activeGraphURL = graphURL
    }

    var filteredNodes: [DroidCodeGraphNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let document else { return [] }
        guard !trimmed.isEmpty else { return document.nodes.sorted { $0.degree > $1.degree } }
        return document.nodes
            .filter {
                $0.label.lowercased().contains(trimmed) ||
                    ($0.sourceFile?.lowercased().contains(trimmed) ?? false)
            }
            .sorted { $0.degree > $1.degree }
    }

    var selectedNode: DroidCodeGraphNode? {
        guard let document, let selectedNodeID else { return nil }
        return document.nodeByID[selectedNodeID]
    }

    func load() {
        isLoading = true
        errorMessage = nil
        refreshVersions()
        let url = activeGraphURL
        Task {
            do {
                let loaded = try await DroidCodeGraphDocumentLoader.loadOffMain(url: url)
                document = loaded
                errorMessage = nil
                if selectedNodeID == nil || loaded.nodeByID[selectedNodeID ?? ""] == nil {
                    selectedNodeID = loaded.nodes.max(by: { $0.degree < $1.degree })?.id
                }
            } catch {
                document = nil
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func loadLatest() {
        activeGraphURL = latestGraphURL
        activeVersionID = nil
        load()
    }

    func loadVersion(_ version: DroidCodeGraphVersionEntry) {
        activeGraphURL = URL(fileURLWithPath: version.droidGraphPath)
        activeVersionID = version.id
        load()
    }

    private func refreshVersions() {
        versions = DroidCodeGraphVersionArchive.loadIndex(projectID: projectID, worktreeID: worktreeID)
    }
}

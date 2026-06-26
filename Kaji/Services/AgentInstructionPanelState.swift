import Foundation

@MainActor
@Observable
final class AgentInstructionPanelState {
    typealias DiscoveryLoader = @Sendable (
        _ projectPath: String,
        _ descriptors: [AgentInstructionAgentDescriptor],
        _ homeDirectory: String
    ) async throws -> [AgentInstructionGroup]

    var groups: [AgentInstructionGroup] = []
    var isLoading = false
    var errorMessage: String?
    var selectedAgentID: String?
    var selectedDocumentID: String?
    @ObservationIgnored private let discoveryLoader: DiscoveryLoader
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var activeRefreshKey: String?
    @ObservationIgnored private var loadedRefreshKey: String?

    init(discoveryLoader: @escaping DiscoveryLoader = AgentInstructionPanelState.defaultDiscoveryLoader) {
        self.discoveryLoader = discoveryLoader
    }

    deinit {
        refreshTask?.cancel()
    }

    var selectedGroup: AgentInstructionGroup? {
        groups.first { $0.id == selectedAgentID } ?? groups.first
    }

    var selectedDocument: AgentInstructionDocument? {
        guard let group = selectedGroup else { return nil }
        return group.documents.first { $0.id == selectedDocumentID } ?? group.documents.first
    }

    func refreshIfNeeded(projectPath: String, enabledLaunchers: [CLILauncherConfiguration]) {
        refresh(projectPath: projectPath, enabledLaunchers: enabledLaunchers, force: false)
    }

    func refresh(projectPath: String, enabledLaunchers: [CLILauncherConfiguration], force: Bool = true) {
        let enabledIDs = Set(enabledLaunchers.map(\.id))
        let descriptors = CodingAgentRegistry.shared.definitions
            .filter { enabledIDs.contains($0.id) }
            .map(AgentInstructionAgentDescriptor.init)
        let key = Self.refreshKey(projectPath: projectPath, descriptors: descriptors)
        guard force || loadedRefreshKey != key else { return }
        guard activeRefreshKey != key || refreshTask == nil else { return }

        refreshTask?.cancel()
        activeRefreshKey = key
        errorMessage = nil
        isLoading = true
        if loadedRefreshKey != key {
            groups = []
            selectedAgentID = nil
            selectedDocumentID = nil
        }

        guard !descriptors.isEmpty else {
            finishRefresh(groups: [], key: key)
            return
        }

        let homeDirectory = NSHomeDirectory()
        let loader = discoveryLoader
        refreshTask = Task { [weak self] in
            do {
                let discovered = try await loader(projectPath, descriptors, homeDirectory)
                guard !Task.isCancelled, let self else { return }
                finishRefresh(groups: discovered, key: key)
            } catch {
                guard !Task.isCancelled, let self else { return }
                failRefresh(error.localizedDescription, key: key)
            }
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        activeRefreshKey = nil
        isLoading = false
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

    private func finishRefresh(groups: [AgentInstructionGroup], key: String) {
        self.groups = groups
        loadedRefreshKey = key
        activeRefreshKey = nil
        refreshTask = nil
        isLoading = false
        errorMessage = nil
        normalizeSelection()
    }

    private func failRefresh(_ message: String, key: String) {
        if loadedRefreshKey != key {
            groups = []
        }
        activeRefreshKey = nil
        refreshTask = nil
        isLoading = false
        errorMessage = message.isEmpty ? "Unknown error" : message
        normalizeSelection()
    }

    private static func refreshKey(projectPath: String, descriptors: [AgentInstructionAgentDescriptor]) -> String {
        ([projectPath] + descriptors.map { descriptor in
            [
                descriptor.id,
                descriptor.globalInstructionFiles.joined(separator: ","),
                descriptor.projectInstructionFiles.joined(separator: ","),
            ].joined(separator: ":")
        }).joined(separator: "|")
    }

    private static let defaultDiscoveryLoader: DiscoveryLoader = { projectPath, descriptors, homeDirectory in
        await GitProcessRunner.offMain {
            AgentInstructionDiscovery.discover(
                projectPath: projectPath,
                descriptors: descriptors,
                homeDirectory: homeDirectory
            )
        }
    }
}

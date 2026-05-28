import Foundation

@MainActor
@Observable
final class CodingAgentProcessMonitorService {
    static let shared = CodingAgentProcessMonitorService()

    private(set) var groups: [CodingAgentProcessProviderGroup] = []
    private(set) var isRefreshing = false
    private(set) var killingPIDs: Set<Int32> = []
    private(set) var statusMessage: String?
    private(set) var statusIsError = false

    private init() {}

    var processCount: Int { groups.reduce(0) { $0 + $1.processes.count } }
    var orphanCount: Int { groups.reduce(0) { $0 + $1.orphanCount } }

    func refresh(appState: AppState, projectStore: ProjectStore) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let activeProcessGroupIDs = Self.activeProcessGroupIDs(appState: appState, projectStore: projectStore)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let processes = try await CodingAgentProcessSnapshotter.snapshot()
                let matches = CodingAgentProcessClassifier.classify(
                    processes: processes,
                    definitions: CodingAgentRegistry.shared.definitions,
                    activeProcessGroupIDs: activeProcessGroupIDs
                )
                groups = CodingAgentProcessAggregator.groups(from: matches)
                statusMessage = nil
                statusIsError = false
            } catch {
                groups = []
                statusMessage = error.localizedDescription
                statusIsError = true
            }
            isRefreshing = false
        }
    }

    func terminate(_ match: CodingAgentProcessMatch, appState: AppState, projectStore: ProjectStore) {
        signal(match, force: false, appState: appState, projectStore: projectStore)
    }

    func forceTerminate(_ match: CodingAgentProcessMatch, appState: AppState, projectStore: ProjectStore) {
        signal(match, force: true, appState: appState, projectStore: projectStore)
    }

    func terminateGroup(_ group: CodingAgentProcessProviderGroup, appState: AppState, projectStore: ProjectStore) {
        let targets = group.processes.filter { !killingPIDs.contains($0.process.pid) }
        guard !targets.isEmpty else { return }
        targets.forEach { killingPIDs.insert($0.process.pid) }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let failures = targets.compactMap { match -> String? in
                do {
                    try CodingAgentProcessKiller.terminate(pid: match.process.pid)
                    return nil
                } catch {
                    return "pid \(match.process.pid): \(error.localizedDescription)"
                }
            }

            if failures.isEmpty {
                statusMessage = "Terminated \(targets.count) \(group.providerName) processes."
                statusIsError = false
            } else {
                statusMessage = failures.joined(separator: "  ")
                statusIsError = true
            }

            targets.forEach { killingPIDs.remove($0.process.pid) }
            refresh(appState: appState, projectStore: projectStore)
        }
    }

    private func signal(_ match: CodingAgentProcessMatch, force: Bool, appState: AppState, projectStore: ProjectStore) {
        guard !killingPIDs.contains(match.process.pid) else { return }
        killingPIDs.insert(match.process.pid)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if force {
                    try CodingAgentProcessKiller.forceTerminate(pid: match.process.pid)
                } else {
                    try CodingAgentProcessKiller.terminate(pid: match.process.pid)
                }
                statusMessage = "Terminated \(match.providerName) pid \(match.process.pid)."
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
            killingPIDs.remove(match.process.pid)
            refresh(appState: appState, projectStore: projectStore)
        }
    }

    private static func activeProcessGroupIDs(appState: AppState, projectStore: ProjectStore) -> Set<Int32> {
        let descriptors = ResourceMonitorTerminalLocator.locate(appState: appState, projects: projectStore.projects)
        return Set(descriptors.compactMap { TerminalViewRegistry.shared.foregroundProcessGroupID(for: $0.paneID) })
    }
}

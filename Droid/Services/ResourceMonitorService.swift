import Foundation

@MainActor
@Observable
final class ResourceMonitorService {
    static let shared = ResourceMonitorService()

    struct RefreshBaseline {
        let cpuTimeNanos: UInt64
        let timestamp: Date
    }

    private(set) var projects: [ResourceMonitorProjectSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var lastRefreshDate: Date?

    private var refreshTask: Task<Void, Never>?
    private var baselines: [Int32: RefreshBaseline] = [:]

    private init() {}

    func start(appState: AppState, projectStore: ProjectStore) {
        guard refreshTask == nil else { return }
        refresh(appState: appState, projectStore: projectStore)
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.refresh(appState: appState, projectStore: projectStore)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(appState: AppState, projectStore: ProjectStore) {
        guard !isRefreshing else { return }
        isRefreshing = true

        let now = Date()
        let descriptors = ResourceMonitorTerminalLocator.locate(appState: appState, projects: projectStore.projects)
        let readings = descriptors.map { buildReading(for: $0, now: now) }
        let activePIDs = Set(readings.compactMap(\.pid))

        projects = ResourceMonitorAggregator.buildProjects(from: readings, orderedProjects: projectStore.projects)
        pruneBaselines(using: activePIDs)
        lastRefreshDate = now
        isRefreshing = false
    }

    private func buildReading(for descriptor: ResourceMonitorTerminalDescriptor, now: Date) -> ResourceMonitorTerminalReading {
        let view = TerminalViewRegistry.shared.view(for: descriptor.paneID)
        let pid = view?.foregroundProcessID()
        let ttyName = view?.ttyName()
        let sample = pid.flatMap(ProcessResourceSampler.sample(pid:))
        let cpuPercent = sample.flatMap { resolveCPUPercent(for: $0, now: now) }

        if let sample {
            baselines[sample.pid] = RefreshBaseline(cpuTimeNanos: sample.cpuTimeNanos, timestamp: now)
        }

        return ResourceMonitorTerminalReading(
            descriptor: descriptor,
            pid: sample?.pid ?? pid,
            processName: sample?.processName,
            ttyName: ttyName,
            cpuPercent: cpuPercent,
            memoryBytes: sample?.memoryBytes,
            threadCount: sample?.threadCount
        )
    }

    private func resolveCPUPercent(for sample: ProcessResourceSample, now: Date) -> Double? {
        guard let baseline = baselines[sample.pid] else { return nil }
        let elapsed = now.timeIntervalSince(baseline.timestamp)
        guard elapsed > 0, sample.cpuTimeNanos >= baseline.cpuTimeNanos else { return nil }
        let delta = Double(sample.cpuTimeNanos - baseline.cpuTimeNanos)
        return (delta / (elapsed * 1_000_000_000)) * 100
    }

    private func pruneBaselines(using activePIDs: Set<Int32>) {
        baselines = baselines.filter { activePIDs.contains($0.key) }
    }
}

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
    private(set) var appSnapshot: ResourceMonitorAppSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastRefreshDate: Date?

    private weak var appState: AppState?
    private weak var projectStore: ProjectStore?
    private var refreshTask: Task<Void, Never>?
    private var baselines: [Int32: RefreshBaseline] = [:]

    private init() {}

    func start(appState: AppState, projectStore: ProjectStore) {
        self.appState = appState
        self.projectStore = projectStore
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

    func restartIfRunning() {
        guard refreshTask != nil, let appState, let projectStore else { return }
        stop()
        baselines.removeAll()
        start(appState: appState, projectStore: projectStore)
    }

    func refresh(appState: AppState, projectStore: ProjectStore) {
        guard !isRefreshing else { return }
        isRefreshing = true

        let now = Date()
        let descriptors = ResourceMonitorTerminalLocator.locate(appState: appState, projects: projectStore.projects)
        let readings = descriptors.map { buildReading(for: $0, now: now) }
        let activeProcessRootIDs = Set(descriptors.compactMap {
            TerminalViewRegistry.shared.terminalProcessRootID(for: $0.paneID)
        })

        appSnapshot = buildAppSnapshot(now: now)
        projects = ResourceMonitorAggregator.buildProjects(from: readings, orderedProjects: projectStore.projects)
        pruneBaselines(using: activeProcessRootIDs)
        lastRefreshDate = now
        isRefreshing = false
    }

    private func buildReading(for descriptor: ResourceMonitorTerminalDescriptor, now: Date) -> ResourceMonitorTerminalReading {
        let view = TerminalViewRegistry.shared.view(for: descriptor.paneID)
        let processRootID = view?.terminalProcessRootID()
        let ttyName = view?.ttyName()
        let sample = processRootID.flatMap(ProcessResourceSampler.sampleProcessTree(rootPID:))
        let cpuPercent = sample.flatMap { resolveCPUPercent(for: $0, now: now) }

        if let sample {
            baselines[sample.rootPID] = RefreshBaseline(
                cpuTimeNanos: sample.cpuTimeNanos,
                timestamp: now
            )
        }

        return ResourceMonitorTerminalReading(
            descriptor: descriptor,
            processGroupID: sample?.representativeProcessGroupID ?? processRootID,
            pid: sample?.representativePID,
            processName: sample?.processName,
            ttyName: ttyName,
            cpuPercent: cpuPercent,
            memoryBytes: sample?.memoryBytes,
            threadCount: sample?.threadCount
        )
    }

    private func resolveCPUPercent(for sample: ProcessTreeResourceSample, now: Date) -> Double? {
        guard let baseline = baselines[sample.rootPID] else { return nil }
        let elapsed = now.timeIntervalSince(baseline.timestamp)
        return ResourceMonitorCPUPercentResolver.resolve(
            currentCPUTimeNanos: sample.cpuTimeNanos,
            baselineCPUTimeNanos: baseline.cpuTimeNanos,
            elapsed: elapsed
        )
    }

    private func resolveCPUPercent(for sample: ProcessGroupResourceSample, now: Date) -> Double? {
        guard let baseline = baselines[sample.processGroupID] else { return nil }
        let elapsed = now.timeIntervalSince(baseline.timestamp)
        return ResourceMonitorCPUPercentResolver.resolve(
            currentCPUTimeNanos: sample.cpuTimeNanos,
            baselineCPUTimeNanos: baseline.cpuTimeNanos,
            elapsed: elapsed
        )
    }

    private func buildAppSnapshot(now: Date) -> ResourceMonitorAppSnapshot? {
        guard let sample = ProcessResourceSampler.sampleCurrentProcess() else { return nil }
        let cpuPercent: Double? = if let baseline = baselines[sample.pid] {
            ResourceMonitorCPUPercentResolver.resolve(
                currentCPUTimeNanos: sample.cpuTimeNanos,
                baselineCPUTimeNanos: baseline.cpuTimeNanos,
                elapsed: now.timeIntervalSince(baseline.timestamp)
            )
        } else {
            nil
        }
        baselines[sample.pid] = RefreshBaseline(cpuTimeNanos: sample.cpuTimeNanos, timestamp: now)
        return ResourceMonitorAppSnapshot(
            id: sample.pid,
            title: "Kaji",
            pid: sample.pid,
            processName: sample.processName,
            cpuPercent: cpuPercent,
            memoryBytes: max(sample.footprintBytes, sample.residentBytes),
            threadCount: sample.threadCount,
            terminalDiagnostics: TerminalSettingsStore.shared.snapshot().telemetryEnabled
                ? TerminalViewRegistry.shared.diagnosticsSnapshot()
                : nil
        )
    }

    private func pruneBaselines(using activeProcessGroupIDs: Set<Int32>) {
        let currentPID = getpid()
        baselines = baselines.filter { activeProcessGroupIDs.contains($0.key) || $0.key == currentPID }
    }
}

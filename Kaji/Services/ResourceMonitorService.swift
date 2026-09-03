import Foundation

@MainActor
@Observable
final class ResourceMonitorService {
    static let shared = ResourceMonitorService()

    struct RefreshBaseline {
        let cpuTimeNanos: UInt64
        let instant: ContinuousClock.Instant
    }

    struct BaselineKey: Hashable {
        let paneID: UUID?
        let pid: Int32
        let startIdentity: ProcessStartIdentity
    }

    enum RefreshHealth: Equatable {
        case waiting
        case healthy
        case stale
        case failed(String)
    }

    private struct SamplingTarget {
        let descriptor: ResourceMonitorTerminalDescriptor
        let rootPID: Int32?
    }

    private struct TerminalSampleResult {
        let descriptor: ResourceMonitorTerminalDescriptor
        let ttyName: String?
        let sample: ProcessTreeResourceSample?
    }

    private struct SamplingResult {
        let terminals: [TerminalSampleResult]
        let app: ProcessResourceSample?
        let instant: ContinuousClock.Instant
    }

    private(set) var projects: [ResourceMonitorProjectSnapshot] = []
    private(set) var appSnapshot: ResourceMonitorAppSnapshot?
    private(set) var isRefreshing = false
    private(set) var lastRefreshDate: Date?
    private var activeRefreshID: UUID?
    private(set) var lastRefreshAttemptDate: Date?
    private(set) var lastRefreshError: String?

    private weak var appState: AppState?
    private weak var projectStore: ProjectStore?
    private var cadenceTask: Task<Void, Never>?
    private var activeRefreshTask: Task<Void, Never>?
    private var baselines: [BaselineKey: RefreshBaseline] = [:]
    private let clock = ContinuousClock()

    private static let refreshInterval = Duration.seconds(5)
    private static let staleAfter: TimeInterval = 12

    private init() {}

    var snapshotAge: TimeInterval? {
        lastRefreshDate.map { max(0, Date().timeIntervalSince($0)) }
    }

    var refreshHealth: RefreshHealth {
        Self.resolveRefreshHealth(
            lastRefreshDate: lastRefreshDate,
            lastRefreshError: lastRefreshError,
            now: Date()
        )
    }

    static func resolveRefreshHealth(
        lastRefreshDate: Date?,
        lastRefreshError: String?,
        now: Date,
        staleAfter: TimeInterval = staleAfter
    ) -> RefreshHealth {
        if let lastRefreshError {
            return .failed(lastRefreshError)
        }
        guard let lastRefreshDate else { return .waiting }
        return now.timeIntervalSince(lastRefreshDate) > staleAfter ? .stale : .healthy
    }

    func start(appState: AppState, projectStore: ProjectStore) {
        self.appState = appState
        self.projectStore = projectStore
        guard cadenceTask == nil else { return }

        cadenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh(appState: appState, projectStore: projectStore)
            var nextRefresh = self.clock.now.advanced(by: Self.refreshInterval)
            while !Task.isCancelled {
                do {
                    try await self.clock.sleep(until: nextRefresh)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refresh(appState: appState, projectStore: projectStore)
                nextRefresh = nextRefresh.advanced(by: Self.refreshInterval)
                if nextRefresh < self.clock.now {
                    nextRefresh = self.clock.now.advanced(by: Self.refreshInterval)
                }
            }
        }
    }

    func stop() {
        cadenceTask?.cancel()
        cadenceTask = nil
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeRefreshID = nil
        isRefreshing = false
    }

    func restartIfRunning() {
        guard cadenceTask != nil, let appState, let projectStore else { return }
        cadenceTask?.cancel()
        cadenceTask = nil
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeRefreshID = nil
        isRefreshing = false
        baselines.removeAll()
        start(appState: appState, projectStore: projectStore)
    }

    func refresh(appState: AppState, projectStore: ProjectStore) async {
        if let activeRefreshTask {
            await activeRefreshTask.value
            return
        }

        self.appState = appState
        self.projectStore = projectStore
        let descriptors = ResourceMonitorTerminalLocator.locate(appState: appState, projects: projectStore.projects)
        let targets = descriptors.map { descriptor in
            SamplingTarget(
                descriptor: descriptor,
                rootPID: TerminalViewRegistry.shared.terminalProcessRootID(for: descriptor.paneID)
            )
        }
        let telemetryEnabled = TerminalSettingsStore.shared.snapshot().telemetryEnabled
        let diagnostics = telemetryEnabled ? TerminalViewRegistry.shared.diagnosticsSnapshot() : nil
        lastRefreshAttemptDate = Date()
        lastRefreshError = nil
        isRefreshing = true

        let refreshID = UUID()
        let task = Task { @MainActor [weak self, weak projectStore] in
            guard let self else { return }
            do {
                let result = try await Self.sample(targets: targets)
                guard !Task.isCancelled, let projectStore else { return }
                self.apply(result: result, orderedProjects: projectStore.projects, diagnostics: diagnostics)
            } catch is CancellationError {
                return
            } catch {
                self.lastRefreshError = error.localizedDescription
            }
            self.isRefreshing = false
        }
        activeRefreshID = refreshID
        activeRefreshTask = task
        await task.value
        if activeRefreshID == refreshID {
            activeRefreshTask = nil
            activeRefreshID = nil
        }
    }

    nonisolated private static func sample(targets: [SamplingTarget]) async throws -> SamplingResult {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let snapshot = try ProcessResourceSampler.snapshot()
            try Task.checkCancellation()
            let terminals = targets.map { target in
                let rootProcess = target.rootPID.flatMap(snapshot.process(pid:))
                let ttyName = rootProcess?.ttyName
                let foregroundProcessGroupID = ProcessResourceSampler.foregroundProcessGroupID(ttyName: ttyName)
                let tree = target.rootPID.flatMap {
                    ProcessResourceSampler.sampleProcessTree(
                        rootPID: $0,
                        snapshot: snapshot,
                        foregroundProcessGroupID: foregroundProcessGroupID
                    )
                }
                return TerminalSampleResult(descriptor: target.descriptor, ttyName: ttyName, sample: tree)
            }
            return SamplingResult(
                terminals: terminals,
                app: snapshot.process(pid: getpid()),
                instant: ContinuousClock().now
            )
        }.value
    }

    private func apply(
        result: SamplingResult,
        orderedProjects: [Project],
        diagnostics: TerminalViewDiagnosticsSnapshot?
    ) {
        var nextBaselines: [BaselineKey: RefreshBaseline] = [:]
        let readings = result.terminals.map { terminal in
            buildReading(for: terminal, instant: result.instant, nextBaselines: &nextBaselines)
        }
        appSnapshot = result.app.map {
            buildAppSnapshot(
                sample: $0,
                diagnostics: diagnostics,
                instant: result.instant,
                nextBaselines: &nextBaselines
            )
        }
        baselines = nextBaselines
        projects = ResourceMonitorAggregator.buildProjects(from: readings, orderedProjects: orderedProjects)
        lastRefreshDate = Date()
        lastRefreshError = nil
    }

    private func buildReading(
        for result: TerminalSampleResult,
        instant: ContinuousClock.Instant,
        nextBaselines: inout [BaselineKey: RefreshBaseline]
    ) -> ResourceMonitorTerminalReading {
        var processUsages: [ResourceMonitorProcessUsage] = []
        if let processes = result.sample?.processes {
            processUsages.reserveCapacity(processes.count)
            for process in processes {
                let key = BaselineKey(
                    paneID: result.descriptor.paneID,
                    pid: process.pid,
                    startIdentity: process.startIdentity
                )
                let cpuPercent = resolveCPUPercent(process: process, key: key, instant: instant)
                nextBaselines[key] = RefreshBaseline(cpuTimeNanos: process.cpuTimeNanos, instant: instant)
                processUsages.append(ResourceMonitorProcessUsage(
                    identity: ResourceMonitorProcessIdentity(pid: process.pid, startIdentity: process.startIdentity),
                    cpuPercent: cpuPercent,
                    memoryBytes: process.memoryBytes
                ))
            }
        }
        let sample = result.sample
        let cpuValues = processUsages.compactMap(\.cpuPercent)

        return ResourceMonitorTerminalReading(
            descriptor: result.descriptor,
            processGroupID: sample?.representativeProcessGroupID,
            pid: sample?.representativePID,
            processName: sample?.processName,
            ttyName: result.ttyName,
            cpuPercent: cpuValues.isEmpty ? nil : cpuValues.reduce(0, +),
            memoryBytes: sample?.memoryBytes,
            threadCount: sample?.threadCount,
            processUsages: processUsages
        )
    }

    private func buildAppSnapshot(
        sample: ProcessResourceSample,
        diagnostics: TerminalViewDiagnosticsSnapshot?,
        instant: ContinuousClock.Instant,
        nextBaselines: inout [BaselineKey: RefreshBaseline]
    ) -> ResourceMonitorAppSnapshot {
        let key = BaselineKey(paneID: nil, pid: sample.pid, startIdentity: sample.startIdentity)
        let cpuPercent = resolveCPUPercent(process: sample, key: key, instant: instant)
        nextBaselines[key] = RefreshBaseline(cpuTimeNanos: sample.cpuTimeNanos, instant: instant)
        return ResourceMonitorAppSnapshot(
            id: sample.pid,
            title: "Kaji",
            pid: sample.pid,
            processName: sample.processName,
            cpuPercent: cpuPercent,
            memoryBytes: sample.memoryBytes,
            threadCount: sample.threadCount,
            terminalDiagnostics: diagnostics
        )
    }

    private func resolveCPUPercent(
        process: ProcessResourceSample,
        key: BaselineKey,
        instant: ContinuousClock.Instant
    ) -> Double? {
        guard let baseline = baselines[key] else { return nil }
        let elapsed = baseline.instant.duration(to: instant).seconds
        return ResourceMonitorCPUPercentResolver.resolve(
            currentCPUTimeNanos: process.cpuTimeNanos,
            baselineCPUTimeNanos: baseline.cpuTimeNanos,
            elapsed: elapsed
        )
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

import Foundation
import os

private let projectRemovalLogger = Logger(subsystem: "app.kaji", category: "ProjectRemoval")

struct ProjectRemovalImpact: Equatable {
    let hasUnsavedEditors: Bool
    let hasRunningTerminals: Bool
    let hasRunningAgents: Bool
    let worktreeCount: Int

    var hasRunningWork: Bool {
        hasRunningTerminals || hasRunningAgents
    }
}

@MainActor
enum ProjectRemovalCoordinator {
    static func impact(project: Project, appState: AppState, worktreeStore: WorktreeStore) -> ProjectRemovalImpact {
        let worktrees = worktreeStore.list(for: project.id)
        return ProjectRemovalImpact(
            hasUnsavedEditors: appState.hasUnsavedEditorTabs(projectID: project.id),
            hasRunningTerminals: appState.hasRunningTerminalProcesses(projectID: project.id),
            hasRunningAgents: AIActivityStore.shared.hasActiveAgent(projectID: project.id),
            worktreeCount: worktrees.count
        )
    }
}

struct ProjectRemovalTombstone: Codable, Equatable, Identifiable {
    let project: Project
    let worktrees: [Worktree]
    let cleanupOnDisk: Bool
    var retryCount: Int

    init(
        project: Project,
        worktrees: [Worktree],
        cleanupOnDisk: Bool,
        retryCount: Int = 0
    ) {
        self.project = project
        self.worktrees = worktrees
        self.cleanupOnDisk = cleanupOnDisk
        self.retryCount = retryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decode(Project.self, forKey: .project)
        worktrees = try container.decode([Worktree].self, forKey: .worktrees)
        cleanupOnDisk = try container.decode(Bool.self, forKey: .cleanupOnDisk)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
    }

    var id: UUID { project.id }
}

protocol ProjectRemovalTombstonePersisting {
    func load() throws -> [ProjectRemovalTombstone]
    func save(_ tombstones: [ProjectRemovalTombstone]) throws
    func quarantine() throws
}

struct FileProjectRemovalTombstonePersistence: ProjectRemovalTombstonePersisting {
    private let store: CodableFileStore<[ProjectRemovalTombstone]>

    init(fileURL: URL = KajiFileStorage.fileURL(filename: "project-removal-tombstones.json")) {
        store = CodableFileStore(fileURL: fileURL, options: .prettySorted)
    }

    func load() throws -> [ProjectRemovalTombstone] {
        try store.load() ?? []
    }

    func save(_ tombstones: [ProjectRemovalTombstone]) throws {
        if tombstones.isEmpty {
            try store.remove()
        } else {
            try store.save(tombstones.sorted { $0.project.id.uuidString < $1.project.id.uuidString })
        }
    }

    func quarantine() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: store.fileURL.path, isDirectory: &isDirectory) else { return }
        let stamp = Self.stampFormatter.string(from: Date())
        let destination = URL(fileURLWithPath: store.fileURL.path + ".stale-\(stamp)")
        try FileManager.default.moveItem(at: store.fileURL, to: destination)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

@MainActor
final class ProjectRemovalService {
    enum Outcome: Equatable {
        case removed
        case alreadyRemoved
        case deferred
    }

    static let shared = ProjectRemovalService()
    static let maxRetryCount = 3

    private enum Source: Equatable {
        case manual
        case alreadyEmptied
        case recovery
    }

    private struct Context {
        let appState: AppState
        let projectStore: ProjectStore
        let worktreeStore: WorktreeStore
    }

    private let tombstones: any ProjectRemovalTombstonePersisting
    private let quiesceIndexes: @Sendable ([String]) async -> Void
    private let cleanupDisk: @Sendable (Project, [Worktree]) async -> Bool
    private var inFlight = Set<UUID>()

    init(
        tombstones: any ProjectRemovalTombstonePersisting = FileProjectRemovalTombstonePersistence(),
        quiesceIndexes: @escaping @Sendable ([String]) async -> Void = { await FFFSearchService.removeIndexes(projectPaths: $0) },
        cleanupDisk: @escaping @Sendable (Project, [Worktree]) async -> Bool = {
            await WorktreeStore.cleanupOnDisk(for: $0, knownWorktrees: $1)
        }
    ) {
        self.tombstones = tombstones
        self.quiesceIndexes = quiesceIndexes
        self.cleanupDisk = cleanupDisk
    }

    func removeManually(
        project: Project,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        cleanupOnDisk: Bool = true
    ) async -> Outcome {
        await begin(
            project: project,
            source: .manual,
            context: Context(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore),
            cleanupOnDisk: cleanupOnDisk
        )
    }

    func finalizeAlreadyEmptied(
        project: Project,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        cleanupOnDisk: Bool = true
    ) async -> Outcome {
        await begin(
            project: project,
            source: .alreadyEmptied,
            context: Context(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore),
            cleanupOnDisk: cleanupOnDisk
        )
    }

    func recoverPendingRemovals(
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) async {
        let pending: [ProjectRemovalTombstone]
        do {
            pending = try tombstones.load()
        } catch {
            projectRemovalLogger.error("Failed to load project removal recovery state: \(error.localizedDescription)")
            return
        }
        for tombstone in pending {
            _ = await execute(
                tombstone: tombstone,
                source: .recovery,
                context: Context(appState: appState, projectStore: projectStore, worktreeStore: worktreeStore)
            )
        }
    }

    private func begin(
        project: Project,
        source: Source,
        context: Context,
        cleanupOnDisk: Bool
    ) async -> Outcome {
        let projectStore = context.projectStore
        let worktreeStore = context.worktreeStore
        guard !inFlight.contains(project.id) else { return .alreadyRemoved }
        var records: [ProjectRemovalTombstone]
        let existingTombstone: ProjectRemovalTombstone?
        do {
            records = try tombstones.load()
            existingTombstone = records.first { $0.id == project.id }
        } catch {
            projectRemovalLogger.error("Failed to read project removal state: \(error.localizedDescription)")
            return .deferred
        }
        guard projectStore.projects.contains(where: { $0.id == project.id }) || existingTombstone != nil else {
            return .alreadyRemoved
        }
        let tombstone = existingTombstone ?? ProjectRemovalTombstone(
            project: project,
            worktrees: worktreeStore.list(for: project.id),
            cleanupOnDisk: cleanupOnDisk
        )
        if existingTombstone == nil {
            do {
                records.removeAll { $0.id == project.id }
                records.append(tombstone)
                try tombstones.save(records)
            } catch {
                projectRemovalLogger.error("Failed to persist project removal state: \(error.localizedDescription)")
                return .deferred
            }
        }
        return await execute(tombstone: tombstone, source: source, context: context)
    }

    private func execute(
        tombstone: ProjectRemovalTombstone,
        source: Source,
        context: Context
    ) async -> Outcome {
        let appState = context.appState
        let projectStore = context.projectStore
        let worktreeStore = context.worktreeStore
        let project = tombstone.project
        guard inFlight.insert(project.id).inserted else { return .alreadyRemoved }
        defer { inFlight.remove(project.id) }

        let paths = Set(([project.path] + tombstone.worktrees.map(\.path)).filter { !$0.isEmpty }).sorted()
        await quiesceIndexes(paths)

        let metadataPaneIDs = Set(appState.terminalPaneIDs(for: project.id) + appState.parentAgentIDs(for: project.id))
            .sorted { $0.uuidString < $1.uuidString }
        let staleMessage = "Project was removed from Kaji."
        KajiAgentStoreRegistry.shared.stop(projectID: project.id)
        AIActivityStore.shared.markProjectStale(projectID: project.id, message: staleMessage)
        CodingAgentSessionMetadataStore.shared.remove(paneIDs: metadataPaneIDs)
        NotificationStore.shared.remove(projectID: project.id)

        let projectAlreadyRemoved = !projectStore.projects.contains { $0.id == project.id }
        let worktreesAlreadyRemoved = worktreeStore.list(for: project.id).isEmpty
        let replacement = deterministicReplacement(removing: project.id, projectStore: projectStore, worktreeStore: worktreeStore)
        if source != .alreadyEmptied {
            appState.removeProject(project.id)
        }
        let projectPersisted = projectAlreadyRemoved || projectStore.remove(id: project.id)
        let worktreesPersisted = worktreesAlreadyRemoved || worktreeStore.removeProject(project.id)
        selectReplacementIfNeeded(replacement, appState: appState)

        let diskCleaned = if tombstone.cleanupOnDisk {
            await cleanupDisk(project, tombstone.worktrees)
        } else {
            true
        }
        guard projectPersisted, worktreesPersisted, diskCleaned else {
            await persistFailure(tombstone, source: source)
            return .deferred
        }
        do {
            var records = try tombstones.load()
            records.removeAll { $0.id == project.id }
            try tombstones.save(records)
        } catch {
            projectRemovalLogger.error("Failed to clear project removal recovery state: \(error.localizedDescription)")
        }
        return .removed
    }

    private func persistFailure(_ tombstone: ProjectRemovalTombstone, source: Source) async {
        do {
            var records = try tombstones.load()
            records.removeAll { $0.id == tombstone.project.id }
            var updated = tombstone
            if source == .recovery {
                updated.retryCount = tombstone.retryCount + 1
            }
            records.append(updated)
            try tombstones.save(records)
        } catch {
            projectRemovalLogger.error("Failed to update project removal recovery state: \(error.localizedDescription)")
            return
        }
        guard source == .recovery,
              tombstone.retryCount + 1 >= ProjectRemovalService.maxRetryCount
        else { return }
        do {
            try tombstones.quarantine()
        } catch {
            projectRemovalLogger.error("Failed to quarantine project removal recovery state: \(error.localizedDescription)")
        }
    }

    private func deterministicReplacement(
        removing projectID: UUID,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) -> (Project, Worktree)? {
        for project in projectStore.projects where project.id != projectID {
            if let worktree = worktreeStore.preferred(for: project.id, matching: nil) {
                return (project, worktree)
            }
        }
        return nil
    }

    private func selectReplacementIfNeeded(_ replacement: (Project, Worktree)?, appState: AppState) {
        guard appState.activeProjectID == nil, let replacement else { return }
        appState.selectProject(replacement.0, worktree: replacement.1)
    }
}

import Foundation
import os

private let kajiCodeGraphRuntimeLogger = Logger(subsystem: "app.kaji", category: "KajiCodeGraphRuntime")

@MainActor
@Observable
final class KajiCodeGraphRuntime {
    static let shared = KajiCodeGraphRuntime()

    var runningKeys: Set<String> = []
    var lastStatus: [String: KajiCodeGraphStatus] = [:]
    var lastError: [String: String] = [:]
    @ObservationIgnored private let finalizer: KajiCodeGraphFinalizer

    init(finalizer: KajiCodeGraphFinalizer = KajiCodeGraphFinalizer()) {
        self.finalizer = finalizer
    }

    func isRunning(projectID: UUID, worktreeID: UUID) -> Bool {
        runningKeys.contains(key(projectID: projectID, worktreeID: worktreeID))
    }

    func hasGraph(projectID: UUID, worktreeID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: kajiGraphURL(projectID: projectID, worktreeID: worktreeID).path)
    }

    func kajiGraphURL(projectID: UUID, worktreeID: UUID) -> URL {
        KajiCodeGraphDirectory.graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("kaji-graph.json")
    }

    func reportURL(projectID: UUID, worktreeID: UUID) -> URL {
        KajiCodeGraphDirectory.graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("GRAPH_REPORT.md")
    }

    func build(
        _ request: KajiCodeGraphRunRequest,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) async {
        await run(
            request,
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
    }

    private func run(
        _ request: KajiCodeGraphRunRequest,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) async {
        let runKey = key(projectID: request.projectID, worktreeID: request.worktreeID)
        guard !runningKeys.contains(runKey) else { return }
        runningKeys.insert(runKey)
        lastError[runKey] = nil
        defer { runningKeys.remove(runKey) }

        do {
            try validateParentAgent()
            try validateGraphifySkill()
            try KajiCodeGraphDirectory.createBaseDirectories()
            let status = try await executeWithParentAgent(
                request,
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
            lastStatus[runKey] = status
        } catch {
            lastError[runKey] = error.localizedDescription
            kajiCodeGraphRuntimeLogger.error("KajiCodeGraph run failed: \(error.localizedDescription)")
        }
    }

    private func validateParentAgent() throws {
        let settings = ParentAgentSettingsStore.shared
        guard settings.readiness.isReady else {
            NotificationCenter.default.post(name: .openParentAgentSettings, object: nil)
            throw KajiCodeGraphInstallerError.commandFailed("Kaji parent agent", 1, settings.readiness.detail)
        }
        guard settings.authStatus.configured else {
            NotificationCenter.default.post(name: .openParentAgentSettings, object: nil)
            throw KajiCodeGraphInstallerError.commandFailed("Kaji parent agent", 1, settings.authStatus.label)
        }
    }

    private func validateGraphifySkill() throws {
        guard FileManager.default.fileExists(atPath: KajiCodeGraphAgentPrompt.skillURL.path) else {
            throw KajiCodeGraphInstallerError.commandFailed(
                "KajiCodeGraph skill",
                1,
                "Graphify skill file is missing. Reinstall KajiCodeGraph from Extensions."
            )
        }
    }

    private func executeWithParentAgent(
        _ request: KajiCodeGraphRunRequest,
        appState: AppState,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore
    ) async throws -> KajiCodeGraphStatus {
        let output = KajiCodeGraphDirectory.graphOutputDirectory(projectID: request.projectID, worktreeID: request.worktreeID)
        let work = output.appendingPathComponent("agent-work", isDirectory: true)
        let buildID = UUID().uuidString
        let snapshot = await KajiCodeGraphGitSnapshot.capture(projectPath: request.projectPath)
        try prepare(output: output, work: work, request: request, buildID: buildID)
        let session = try KajiCodeGraphAgentCoordinator.shared.start(
            request: request,
            prompt: KajiCodeGraphAgentPrompt.make(request: request, output: output, work: work, buildID: buildID),
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
        let status = try await waitForFinalStatus(output: output, work: work, request: request, buildID: buildID, session: session)
        if status.ok {
            _ = try KajiCodeGraphVersionArchive.record(
                projectID: request.projectID,
                worktreeID: request.worktreeID,
                outputDirectory: output,
                snapshot: snapshot
            )
        }
        return status
    }

    private func prepare(output: URL, work: URL, request: KajiCodeGraphRunRequest, buildID: String) throws {
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try writeStatus(output: output, request: request, buildID: buildID)
    }

    private func writeStatus(output: URL, request: KajiCodeGraphRunRequest, buildID: String) throws {
        let payload: [String: Any] = [
            "ok": false,
            "mode": request.mode,
            "nodes": 0,
            "edges": 0,
            "communities": 0,
            "graphPath": output.appendingPathComponent("graph.json").path,
            "kajiGraphPath": output.appendingPathComponent("kaji-graph.json").path,
            "reportPath": output.appendingPathComponent("GRAPH_REPORT.md").path,
            "buildID": buildID,
            "state": "running",
            "message": "Parent Agent launched Graphify build",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("status.json"), options: .atomic)
    }

    private func waitForFinalStatus(
        output: URL,
        work: URL,
        request: KajiCodeGraphRunRequest,
        buildID: String,
        session: KajiCodeGraphAgentSession
    ) async throws -> KajiCodeGraphStatus {
        let deadline = Date().addingTimeInterval(14400)
        while Date() < deadline {
            if let status = finalizer.readFinalStatus(output: output, buildID: buildID) {
                return status
            }
            if let status = try await finalizer.finalizeIfReady(request: request, output: output, work: work, buildID: buildID) {
                return status
            }
            if session.status.isTerminal {
                throw KajiCodeGraphInstallerError.commandFailed(
                    "KajiCodeGraph agent build",
                    1,
                    "Graph agent finished before producing importable Graphify output."
                )
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw KajiCodeGraphInstallerError.commandFailed("KajiCodeGraph agent build", 124, "Timed out waiting for Graphify finalizer.")
    }

    private func key(projectID: UUID, worktreeID: UUID) -> String {
        "\(projectID.uuidString)-\(worktreeID.uuidString)"
    }
}

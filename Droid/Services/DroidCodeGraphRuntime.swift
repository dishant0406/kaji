import Foundation
import os

private let droidCodeGraphRuntimeLogger = Logger(subsystem: "app.droid", category: "DroidCodeGraphRuntime")

@MainActor
@Observable
final class DroidCodeGraphRuntime {
    static let shared = DroidCodeGraphRuntime()

    var runningKeys: Set<String> = []
    var lastStatus: [String: DroidCodeGraphStatus] = [:]
    var lastError: [String: String] = [:]

    private let runner: any DroidCodeGraphProcessRunning

    init(runner: any DroidCodeGraphProcessRunning = DroidCodeGraphProcessRunner()) {
        self.runner = runner
    }

    func isRunning(projectID: UUID, worktreeID: UUID) -> Bool {
        runningKeys.contains(key(projectID: projectID, worktreeID: worktreeID))
    }

    func hasGraph(projectID: UUID, worktreeID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: droidGraphURL(projectID: projectID, worktreeID: worktreeID).path)
    }

    func droidGraphURL(projectID: UUID, worktreeID: UUID) -> URL {
        DroidCodeGraphDirectory.graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("droid-graph.json")
    }

    func reportURL(projectID: UUID, worktreeID: UUID) -> URL {
        DroidCodeGraphDirectory.graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("GRAPH_REPORT.md")
    }

    func build(_ request: DroidCodeGraphRunRequest) async {
        await run(request)
    }

    private func run(_ request: DroidCodeGraphRunRequest) async {
        let runKey = key(projectID: request.projectID, worktreeID: request.worktreeID)
        guard !runningKeys.contains(runKey) else { return }
        runningKeys.insert(runKey)
        lastError[runKey] = nil
        defer { runningKeys.remove(runKey) }

        do {
            try DroidCodeGraphDirectory.createBaseDirectories()
            try FileManager.default.createDirectory(
                at: DroidCodeGraphDirectory.graphOutputDirectory(projectID: request.projectID, worktreeID: request.worktreeID),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let status = try await execute(request)
            lastStatus[runKey] = status
        } catch {
            lastError[runKey] = error.localizedDescription
            droidCodeGraphRuntimeLogger.error("DroidCodeGraph run failed: \(error.localizedDescription)")
        }
    }

    private func execute(_ request: DroidCodeGraphRunRequest) async throws -> DroidCodeGraphStatus {
        let out = DroidCodeGraphDirectory.graphOutputDirectory(
            projectID: request.projectID,
            worktreeID: request.worktreeID
        )
        let snapshot = await DroidCodeGraphGitSnapshot.capture(projectPath: request.projectPath)
        let result = try await runner.run(
            executable: DroidCodeGraphDirectory.python.path,
            arguments: [
                DroidCodeGraphDirectory.adapterScript.path,
                request.mode,
                "--project",
                request.projectPath,
                "--out",
                out.path,
            ],
            workingDirectory: request.projectPath,
            environment: [
                "PYTHONPATH": DroidCodeGraphDirectory.graphify.path,
                "GRAPHIFY_VIZ_NODE_LIMIT": "0",
            ]
        )
        guard result.status == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DroidCodeGraphInstallerError.commandFailed("droidcodegraph \(request.mode)", result.status, detail)
        }
        let data = try Data(contentsOf: out.appendingPathComponent("status.json"))
        _ = try DroidCodeGraphVersionArchive.record(
            projectID: request.projectID,
            worktreeID: request.worktreeID,
            outputDirectory: out,
            snapshot: snapshot
        )
        return try JSONDecoder().decode(DroidCodeGraphStatus.self, from: data)
    }

    private func key(projectID: UUID, worktreeID: UUID) -> String {
        "\(projectID.uuidString)-\(worktreeID.uuidString)"
    }
}

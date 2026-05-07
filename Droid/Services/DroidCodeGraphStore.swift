import Foundation
import os

private let droidCodeGraphStoreLogger = Logger(subsystem: "app.droid", category: "DroidCodeGraphStore")

@MainActor
@Observable
final class DroidCodeGraphStore {
    static let shared = DroidCodeGraphStore()

    var state: DroidCodeGraphExtensionState

    private let store: CodableFileStore<DroidCodeGraphExtensionState>

    init(fileURL: URL = DroidCodeGraphDirectory.stateFile) {
        store = CodableFileStore(fileURL: fileURL, options: .prettySorted)
        do {
            state = try store.load() ?? .initial
        } catch {
            state = .initial
            droidCodeGraphStoreLogger.error("Failed to load DroidCodeGraph state: \(error.localizedDescription)")
        }
        refreshFromDisk()
    }

    var isInstalled: Bool {
        state.phase == .installed && FileManager.default.isExecutableFile(atPath: pythonURL.path)
    }

    var isReady: Bool {
        isInstalled && state.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        state.isEnabled = enabled
        save()
    }

    func markInstalled(commit: String?, message: String?) {
        state.phase = .installed
        state.isEnabled = true
        state.graphifyCommit = commit
        state.installedAt = Date()
        state.message = message
        save()
    }

    func markFailed(_ message: String) {
        state.phase = .failed
        state.isEnabled = false
        state.message = message
        save()
    }

    func refreshFromDisk() {
        guard state.phase == .installed else { return }
        if !FileManager.default.isExecutableFile(atPath: pythonURL.path) {
            state.phase = .notInstalled
            state.isEnabled = false
            state.message = "Runtime is missing"
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try store.save(state)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.fileURL.path)
        } catch {
            droidCodeGraphStoreLogger.error("Failed to save DroidCodeGraph state: \(error.localizedDescription)")
        }
    }

    var rootDirectory: URL {
        store.fileURL.deletingLastPathComponent()
    }

    func graphOutputDirectory(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("graphify-out", isDirectory: true)
    }

    func projectDirectory(projectID: UUID, worktreeID: UUID) -> URL {
        rootDirectory
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(worktreeID.uuidString, isDirectory: true)
    }

    func droidGraphURL(projectID: UUID, worktreeID: UUID) -> URL {
        graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("droid-graph.json")
    }

    func reportURL(projectID: UUID, worktreeID: UUID) -> URL {
        graphOutputDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("GRAPH_REPORT.md")
    }

    func instructionFile(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("instructions", isDirectory: true)
            .appendingPathComponent("AGENTS.md")
    }

    func codexBridgeFile(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("AGENTS.md")
    }

    func claudeBridgeFile(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("CLAUDE.md")
    }

    func openCodeConfigFile(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("opencode.json")
    }

    private var pythonURL: URL {
        rootDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin")
            .appendingPathComponent("python")
    }
}

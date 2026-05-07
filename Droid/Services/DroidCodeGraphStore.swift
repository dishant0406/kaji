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
        state.phase == .installed && FileManager.default.isExecutableFile(atPath: DroidCodeGraphDirectory.python.path)
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
        if !FileManager.default.isExecutableFile(atPath: DroidCodeGraphDirectory.python.path) {
            state.phase = .notInstalled
            state.isEnabled = false
            state.message = "Runtime is missing"
            save()
        }
    }

    private func save() {
        do {
            try DroidCodeGraphDirectory.createBaseDirectories()
            try store.save(state)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: DroidCodeGraphDirectory.stateFile.path)
        } catch {
            droidCodeGraphStoreLogger.error("Failed to save DroidCodeGraph state: \(error.localizedDescription)")
        }
    }
}

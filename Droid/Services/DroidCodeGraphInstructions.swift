import Foundation

@MainActor
enum DroidCodeGraphInstructions {
    static func ensureFile(
        projectID: UUID,
        worktreeID: UUID,
        store: DroidCodeGraphStore = .shared,
        fileManager: FileManager = .default
    ) -> URL? {
        guard store.isReady else { return nil }
        let graphURL = store.droidGraphURL(projectID: projectID, worktreeID: worktreeID)
        guard fileManager.fileExists(atPath: graphURL.path) else { return nil }
        let destination = store.instructionFile(projectID: projectID, worktreeID: worktreeID)
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if !fileManager.fileExists(atPath: destination.path) {
                let content = defaultText(projectID: projectID, worktreeID: worktreeID, store: store)
                try Data(content.utf8).write(to: destination, options: .atomic)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        } catch {
            return nil
        }
    }

    static func environment(
        projectID: UUID,
        worktreeID: UUID,
        store: DroidCodeGraphStore = .shared,
        fileManager: FileManager = .default
    ) -> [(key: String, value: String)] {
        guard let file = ensureFile(
            projectID: projectID,
            worktreeID: worktreeID,
            store: store,
            fileManager: fileManager
        )
        else { return [] }
        return [
            (key: "DROID_CODE_GRAPH_INSTRUCTIONS", value: file.path),
            (
                key: "DROID_CODE_GRAPH_REPORT",
                value: store.reportURL(projectID: projectID, worktreeID: worktreeID).path
            ),
            (
                key: "DROID_CODE_GRAPH_JSON",
                value: store.droidGraphURL(projectID: projectID, worktreeID: worktreeID).path
            ),
        ]
    }

    static func ensureClaudeBridge(projectID: UUID, worktreeID: UUID, fileManager: FileManager = .default) -> URL? {
        let destination = DroidCodeGraphDirectory.claudeBridgeFile(projectID: projectID, worktreeID: worktreeID)
        let content = ["# Droid Project Instructions", "", "@instructions/AGENTS.md"].joined(separator: "\n")
        return writeLaunchFile(destination, content: content, fileManager: fileManager)
    }

    static func ensureCodexBridge(projectID: UUID, worktreeID: UUID, fileManager: FileManager = .default) -> URL? {
        let destination = DroidCodeGraphDirectory.codexBridgeFile(projectID: projectID, worktreeID: worktreeID)
        let content = [
            "# Droid Project Instructions",
            "",
            "Read instructions/AGENTS.md before answering architecture, dependency, or codebase navigation questions.",
        ].joined(separator: "\n")
        return writeLaunchFile(destination, content: content, fileManager: fileManager)
    }

    static func ensureOpenCodeConfig(
        projectID: UUID,
        worktreeID: UUID,
        instructionFile: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let destination = DroidCodeGraphDirectory.openCodeConfigFile(projectID: projectID, worktreeID: worktreeID)
        let payload: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "instructions": [instructionFile.path],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let content = String(data: data, encoding: .utf8)
        else { return nil }
        return writeLaunchFile(destination, content: content, fileManager: fileManager)
    }

    private static func defaultText(projectID: UUID, worktreeID: UUID, store: DroidCodeGraphStore) -> String {
        let graphURL = store.droidGraphURL(projectID: projectID, worktreeID: worktreeID)
        let reportURL = store.reportURL(projectID: projectID, worktreeID: worktreeID)
        return [
            "# Droid Project Instructions",
            "",
            "These instructions are owned by Droid and apply only to agent sessions launched from Droid.",
            "",
            "## Droid Code Graph",
            "",
            "- Read \(reportURL.path) before answering architecture, dependency, or codebase navigation questions.",
            "- Use \(graphURL.path) as the machine-readable graph when exact nodes, edges, communities, or source files are needed.",
        ].joined(separator: "\n")
    }

    private static func writeLaunchFile(_ destination: URL, content: String, fileManager: FileManager) -> URL? {
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data(content.utf8).write(to: destination, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        } catch {
            return nil
        }
    }
}

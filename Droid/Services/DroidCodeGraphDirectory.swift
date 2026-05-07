import Foundation

enum DroidCodeGraphDirectory {
    private static let overrideKey = "DROID_EXTENSIONS_DIR"

    static var root: URL {
        let base: URL = if let override = ProcessInfo.processInfo.environment[overrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            URL(fileURLWithPath: override, isDirectory: true)
        } else {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".droid", isDirectory: true)
                .appendingPathComponent("extensions", isDirectory: true)
        }
        return base.appendingPathComponent("droidcodegraph", isDirectory: true)
    }

    static var graphify: URL {
        root.appendingPathComponent("graphify", isDirectory: true)
    }

    static var venv: URL {
        root.appendingPathComponent(".venv", isDirectory: true)
    }

    static var python: URL {
        venv.appendingPathComponent("bin/python")
    }

    static var adapter: URL {
        root.appendingPathComponent("adapter", isDirectory: true)
    }

    static var adapterScript: URL {
        adapter.appendingPathComponent("droidcodegraph_runner.py")
    }

    static var stateFile: URL {
        root.appendingPathComponent("state.json")
    }

    static var logDirectory: URL {
        root.appendingPathComponent("logs", isDirectory: true)
    }

    static func projectDirectory(projectID: UUID, worktreeID: UUID) -> URL {
        root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(worktreeID.uuidString, isDirectory: true)
    }

    static func graphOutputDirectory(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("graphify-out", isDirectory: true)
    }

    static func graphVersionsDirectory(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("versions", isDirectory: true)
    }

    static func graphVersionDirectory(projectID: UUID, worktreeID: UUID, versionID: String) -> URL {
        graphVersionsDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent(versionID, isDirectory: true)
    }

    static func graphVersionsIndex(projectID: UUID, worktreeID: UUID) -> URL {
        graphVersionsDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("index.json")
    }

    static func instructionDirectory(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("instructions", isDirectory: true)
    }

    static func instructionFile(projectID: UUID, worktreeID: UUID) -> URL {
        instructionDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("AGENTS.md")
    }

    static func codexBridgeFile(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("AGENTS.md")
    }

    static func claudeBridgeFile(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("CLAUDE.md")
    }

    static func openCodeConfigFile(projectID: UUID, worktreeID: UUID) -> URL {
        projectDirectory(projectID: projectID, worktreeID: worktreeID)
            .appendingPathComponent("opencode.json")
    }

    static func createBaseDirectories() throws {
        let manager = FileManager.default
        for url in [root, adapter, logDirectory] {
            try manager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }
}

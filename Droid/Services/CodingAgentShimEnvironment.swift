import Foundation

@MainActor
enum CodingAgentShimEnvironment {
    static let pathKey = "DROID_AGENT_SHIM_DIR"

    static func variables(
        projectID: UUID,
        worktreeID: UUID,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [(key: String, value: String)] {
        guard let shimDirectory = CodingAgentShimInstaller.install(homeDirectory: homeDirectory, fileManager: fileManager) else {
            return []
        }
        var values = [
            (key: pathKey, value: shimDirectory.path),
            (key: "PATH", value: pathValue(shimDirectory: shimDirectory, environment: environment)),
        ]
        values.append(contentsOf: DroidShellBootstrapInstaller.install(
            homeDirectory: homeDirectory,
            userZdotdir: environment[DroidShellBootstrapInstaller.zdotdirKey],
            fileManager: fileManager
        ))

        values.append(contentsOf: realExecutableVariables(
            environment: environment,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            shimDirectory: shimDirectory
        ))

        guard let instructions = DroidCodeGraphInstructions.ensureFile(projectID: projectID, worktreeID: worktreeID) else {
            return values
        }
        values.append((key: "DROID_CODE_GRAPH_PROJECT_DIR", value: DroidCodeGraphDirectory.projectDirectory(
            projectID: projectID,
            worktreeID: worktreeID
        ).path))
        _ = DroidCodeGraphInstructions.ensureClaudeBridge(projectID: projectID, worktreeID: worktreeID)
        if let config = DroidCodeGraphInstructions.ensureOpenCodeConfig(
            projectID: projectID,
            worktreeID: worktreeID,
            instructionFile: instructions
        ) {
            values.append((key: "DROID_CODE_GRAPH_OPENCODE_CONFIG", value: config.path))
        }
        return values
    }

    private static func pathValue(shimDirectory: URL, environment: [String: String]) -> String {
        let existing = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let parts = existing.split(separator: ":").map(String.init).filter { $0 != shimDirectory.path }
        return ([shimDirectory.path] + parts).joined(separator: ":")
    }

    private static func realExecutableVariables(
        environment: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        shimDirectory: URL
    ) -> [(key: String, value: String)] {
        [
            ("codex", "DROID_REAL_CODEX"),
            ("claude", "DROID_REAL_CLAUDE"),
            ("claude-code", "DROID_REAL_CLAUDE_CODE"),
            ("opencode", "DROID_REAL_OPENCODE"),
            ("pi", "DROID_REAL_PI"),
        ].compactMap { name, key in
            guard let path = realExecutable(
                name,
                environment: environment,
                homeDirectory: homeDirectory,
                fileManager: fileManager,
                shimDirectory: shimDirectory
            )
            else { return nil }
            return (key: key, value: path)
        }
    }

    private static func realExecutable(
        _ name: String,
        environment: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        shimDirectory: URL
    ) -> String? {
        var env = environment
        env["PATH"] = env["PATH"]?
            .split(separator: ":")
            .map(String.init)
            .filter { $0 != shimDirectory.path }
            .joined(separator: ":")
        return AIProviderExecutableLocator.candidatePaths(
            for: name,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        .first { !$0.hasPrefix(shimDirectory.path + "/") && fileManager.isExecutableFile(atPath: $0) }
    }
}

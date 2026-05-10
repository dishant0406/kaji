import Foundation

@MainActor
enum CodingAgentShimEnvironment {
    static let pathKey = "DROID_AGENT_SHIM_DIR"

    static func variables(
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        store: DroidCodeGraphStore = .shared,
        fileManager: FileManager = .default,
        browserEnabled: Bool = BrowserExtensionPreferences.isEnabled
    ) -> [(key: String, value: String)] {
        guard let shimDirectory = CodingAgentShimInstaller.install(
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            installBrowserMCP: browserEnabled
        )
        else {
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
        guard browserEnabled else {
            CodingAgentBrowserEnvironment.removeConfigs(homeDirectory: homeDirectory, fileManager: fileManager)
            DroidBrowserSessionEnvironmentStore.remove(homeDirectory: homeDirectory, fileManager: fileManager)
            return valuesWithCodeGraph(
                values,
                context: CodeGraphEnvironmentContext(
                    projectID: projectID,
                    worktreeID: worktreeID,
                    store: store,
                    fileManager: fileManager,
                    browserMCPDescriptor: nil
                )
            )
        }

        let browserValues = DroidBrowserAgentEnvironment.variables(
            sessionID: worktreeID.uuidString,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            browserEnabled: true
        )
        let browserMCPDescriptor = CodingAgentBrowserEnvironment.descriptor(browserValues)
        values.append(contentsOf: browserValues)
        values.append(contentsOf: CodingAgentBrowserEnvironment.variables(
            browserValues: browserValues,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ))

        return valuesWithCodeGraph(
            values,
            context: CodeGraphEnvironmentContext(
                projectID: projectID,
                worktreeID: worktreeID,
                store: store,
                fileManager: fileManager,
                browserMCPDescriptor: browserMCPDescriptor
            )
        )
    }

    private struct CodeGraphEnvironmentContext {
        let projectID: UUID
        let worktreeID: UUID
        let store: DroidCodeGraphStore
        let fileManager: FileManager
        let browserMCPDescriptor: DroidBrowserMCPServerDescriptor?
    }

    private static func valuesWithCodeGraph(
        _ baseValues: [(key: String, value: String)],
        context: CodeGraphEnvironmentContext
    ) -> [(key: String, value: String)] {
        var values = baseValues
        guard context.store.isReady,
              let instructions = DroidCodeGraphInstructions.ensureFile(
                  projectID: context.projectID,
                  worktreeID: context.worktreeID,
                  store: context.store,
                  fileManager: context.fileManager
              )
        else { return values }

        values.append((key: "DROID_CODE_GRAPH_ROOT_DIR", value: context.store.rootDirectory.path))
        values.append((
            key: "DROID_CODE_GRAPH_PROJECT_DIR",
            value: context.store.projectDirectory(projectID: context.projectID, worktreeID: context.worktreeID).path
        ))
        values.append(contentsOf: DroidCodeGraphInstructions.environment(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            store: context.store,
            fileManager: context.fileManager
        ))
        _ = DroidCodeGraphInstructions.ensureCodexBridge(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            store: context.store,
            fileManager: context.fileManager
        )
        _ = DroidCodeGraphInstructions.ensureClaudeBridge(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            store: context.store,
            fileManager: context.fileManager
        )
        if let config = DroidCodeGraphInstructions.ensureOpenCodeConfig(
            projectID: context.projectID,
            worktreeID: context.worktreeID,
            instructionFile: instructions,
            browserDescriptor: context.browserMCPDescriptor,
            store: context.store,
            fileManager: context.fileManager
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
        return AIProviderExecutableLocator.preferredRealPath(
            for: name,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            excluding: shimDirectory
        )
    }
}

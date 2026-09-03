import Foundation

enum AIGatewayClaudeCodeRouterInstaller {
    static func state(fileManager: FileManager = .default) -> AIGatewayInstallState {
        let command = AIGatewayClaudeCodeRouterPaths.commandURL()
        guard fileManager.fileExists(atPath: command.path) else { return .missing }
        guard fileManager.isExecutableFile(atPath: command.path) else {
            return .needsRepair("Claude Code Router command is not executable.")
        }
        guard let manifest = readManifest(fileManager: fileManager), manifest.matchesCurrentPackage else {
            return .needsRepair("Claude Code Router install manifest is missing or outdated.")
        }
        return .installed
    }

    static func install(fileManager: FileManager = .default) -> AIGatewayInstallResult {
        do {
            let runtime = try AIGatewayManagedNodeInstaller.install(fileManager: fileManager)
            try prepareInstallDirectory(fileManager: fileManager)
            let result = try runNPMInstall(runtime: runtime)
            guard result.exitCode == 0 else {
                return AIGatewayInstallResult(state: .needsRepair(result.output), message: result.output)
            }
            try writeManifest(.current(nodeVersion: runtime.version), fileManager: fileManager)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: AIGatewayClaudeCodeRouterPaths.commandURL().path)
            return AIGatewayInstallResult(state: .installed, message: "Installed Claude Code Router.")
        } catch {
            return AIGatewayInstallResult(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
    }

    static func ensureCurrent(fileManager: FileManager = .default) -> AIGatewayInstallResult {
        if state(fileManager: fileManager) == .installed {
            return AIGatewayInstallResult(state: .installed, message: "Claude Code Router is current.")
        }
        return install(fileManager: fileManager)
    }

    static func uninstall(fileManager: FileManager = .default) -> AIGatewayInstallResult {
        do {
            let directory = AIGatewayClaudeCodeRouterPaths.packageDirectory()
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try? fileManager.removeItem(at: AIGatewayClaudeCodeRouterPaths.manifestURL())
            return AIGatewayInstallResult(state: .missing, message: "Uninstalled Claude Code Router.")
        } catch {
            return AIGatewayInstallResult(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
    }

    private static func prepareInstallDirectory(fileManager: FileManager) throws {
        let directory = AIGatewayClaudeCodeRouterPaths.packageDirectory()
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private static func runNPMInstall(runtime: AIGatewayNodeRuntime) throws -> AIGatewayProcessResult {
        var env = TerminalEnvironmentPolicy.sanitizedEnvironment(from: ProcessInfo.processInfo.environment)
        env["NODE_TLS_REJECT_UNAUTHORIZED"] = nil
        env["PATH"] = runtime.nodeURL.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "")
        return try AIGatewayProcessRunner.run(
            executableURL: runtime.npmURL,
            arguments: installArguments(),
            currentDirectoryURL: AIGatewayClaudeCodeRouterPaths.packageDirectory(),
            environment: env,
            timeout: 240
        )
    }

    static func installArguments() -> [String] {
        [
            "install",
            "\(AIGatewayClaudeCodeRouterPaths.packageName)@\(AIGatewayClaudeCodeRouterPaths.packageVersion)",
            "--omit=dev",
            "--no-audit",
            "--no-fund",
        ]
    }

    private static func readManifest(fileManager: FileManager) -> AIGatewayClaudeCodeRouterManifest? {
        let url = AIGatewayClaudeCodeRouterPaths.manifestURL()
        guard fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AIGatewayClaudeCodeRouterManifest.self, from: data)
    }

    private static func writeManifest(_ manifest: AIGatewayClaudeCodeRouterManifest, fileManager: FileManager) throws {
        let url = AIGatewayClaudeCodeRouterPaths.manifestURL()
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

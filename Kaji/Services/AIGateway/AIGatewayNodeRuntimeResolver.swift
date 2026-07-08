import Foundation

struct AIGatewayNodeRuntime: Equatable {
    let nodeURL: URL
    let npmURL: URL
    let version: String
}

enum AIGatewayNodeRuntimeResolver {
    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> AIGatewayNodeRuntime? {
        let extraDirectories = [managedBinDirectory().path]
        guard let node = AIProviderExecutableLocator.resolvePath(
            for: "node",
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            extraDirectories: extraDirectories
        ), let npm = AIProviderExecutableLocator.resolvePath(
            for: "npm",
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            extraDirectories: extraDirectories
        )
        else { return nil }
        guard let version = readNodeVersion(nodeURL: URL(fileURLWithPath: node)), supportsNode22(version) else { return nil }
        return AIGatewayNodeRuntime(nodeURL: URL(fileURLWithPath: node), npmURL: URL(fileURLWithPath: npm), version: version)
    }

    static func supportsNode22(_ version: String) -> Bool {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        guard let major = value.split(separator: ".").first.flatMap({ Int($0) }) else { return false }
        return major >= 22
    }

    static func managedBinDirectory() -> URL {
        AIGatewayClaudeCodeRouterPaths.toolsDirectory()
            .appendingPathComponent("node-\(AIGatewayClaudeCodeRouterPaths.nodeVersion)", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private static func readNodeVersion(nodeURL: URL) -> String? {
        guard let result = try? AIGatewayProcessRunner.run(executableURL: nodeURL, arguments: ["--version"], timeout: 5) else {
            return nil
        }
        guard result.exitCode == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

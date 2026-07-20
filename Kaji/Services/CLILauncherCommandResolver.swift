import Foundation

enum CLILauncherCommandResolver {
    static func resolve(
        _ command: String,
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let executable = executableToken(in: trimmed) else { return trimmed }
        guard !executable.contains("/") else { return trimmed }
        guard isResolvable(executable) else { return trimmed }
        let legacyShimDirectory = legacyShimDirectory(homeDirectory: homeDirectory)
        guard let agent = CodingAgentRegistry.shared.agent(executableName: executable),
              let resolved = agent.resolveExecutable(
                  env: env,
                  homeDirectory: homeDirectory,
                  fileManager: fileManager,
                  excluding: legacyShimDirectory
              )
        else { return trimmed }
        let suffix = trimmed.dropFirst(executable.count)
        return ShellEscaper.escape(resolved.path) + suffix
    }

    private static func executableToken(in command: String) -> String? {
        guard let first = command.first else { return nil }
        guard first != "'", first != "\"" else { return nil }
        return command.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    private static func isResolvable(_ executable: String) -> Bool {
        !executable.contains("=") && !["env", "sudo", "arch"].contains(executable)
    }

    private static func legacyShimDirectory(homeDirectory: String) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".kaji", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }
}

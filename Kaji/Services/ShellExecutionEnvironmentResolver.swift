import Foundation

enum ShellExecutionEnvironmentResolver {
    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [String: String] {
        guard let shell = ShellExecutableResolver.shellURL(env: env, fileManager: fileManager) else {
            return ShellExecutableResolver.shellEnvironment(env: env, homeDirectory: homeDirectory)
        }
        let base = ShellExecutableResolver.shellEnvironment(env: env, homeDirectory: homeDirectory)
        let login = run(shell: shell, arguments: ["-lc", "env -0"], environment: base, timeout: .seconds(5))
        if !login.isEmpty {
            return base.merging(login) { _, new in new }
        }
        let interactive = run(shell: shell, arguments: ["-i", "-c", "env -0"], environment: base, timeout: .seconds(8))
        return interactive.isEmpty ? base : base.merging(interactive) { _, new in new }
    }

    static func mcpEnvironment(from environment: [String: String]) -> [String: String] {
        guard let path = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else { return [:] }
        return ["PATH": path]
    }

    private static func run(
        shell: URL,
        arguments: [String],
        environment: [String: String],
        timeout: DispatchTimeInterval
    ) -> [String: String] {
        let process = Process()
        process.executableURL = shell
        process.arguments = arguments
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return [:]
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
            return [:]
        }
        guard process.terminationStatus == 0 else { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return parse(data)
    }

    private static func parse(_ data: Data) -> [String: String] {
        var result = [String: String]()
        for item in data.split(separator: 0) {
            guard let text = String(data: Data(item), encoding: .utf8),
                  let index = text.firstIndex(of: "=")
            else { continue }
            let key = String(text[..<index])
            guard !key.isEmpty else { continue }
            result[key] = String(text[text.index(after: index)...])
        }
        return result
    }
}

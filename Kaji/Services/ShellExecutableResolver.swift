import Darwin
import Foundation

enum ShellExecutableResolver {
    static func resolvePaths(
        for executableName: String,
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [String] {
        guard isPlainExecutableName(executableName),
              let shell = shellURL(env: env, fileManager: fileManager)
        else { return [] }

        let script = lookupScript(for: executableName)
        let environment = shellEnvironment(env: env, homeDirectory: homeDirectory)
        let loginPaths = runLookup(
            shell: shell,
            arguments: ["-lc", script],
            environment: environment,
            fileManager: fileManager,
            timeout: .seconds(5)
        )
        if !loginPaths.isEmpty {
            return loginPaths
        }

        return runLookup(
            shell: shell,
            arguments: ["-i", "-c", script],
            environment: environment,
            fileManager: fileManager,
            timeout: .seconds(8)
        )
    }

    private static func runLookup(
        shell: URL,
        arguments: [String],
        environment: [String: String],
        fileManager: FileManager,
        timeout: DispatchTimeInterval
    ) -> [String] {
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
            return []
        }

        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return executablePaths(from: text, fileManager: fileManager)
    }

    static func shellURL(env: [String: String], fileManager: FileManager) -> URL? {
        if let value = env["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty,
           fileManager.isExecutableFile(atPath: value)
        {
            return URL(fileURLWithPath: value)
        }
        guard let passwd = getpwuid(getuid()),
              let shell = passwd.pointee.pw_shell,
              !String(cString: shell).isEmpty
        else { return nil }
        let path = String(cString: shell)
        return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    static func shellEnvironment(env: [String: String], homeDirectory: String) -> [String: String] {
        ProcessInfo.processInfo.environment.merging(env) { _, new in new }.merging(["HOME": homeDirectory]) { _, new in new }
    }

    private static func lookupScript(for executableName: String) -> String {
        let name = shellQuoted(executableName)
        return [
            "if command -v whence >/dev/null 2>&1; then whence -pa -- \(name);",
            "elif command -v where >/dev/null 2>&1; then where -p -- \(name);",
            "elif command -v which >/dev/null 2>&1; then which -a -- \(name);",
            "else command -v -- \(name); fi",
        ].joined(separator: " ")
    }

    private static func executablePaths(from text: String, fileManager: FileManager) -> [String] {
        var paths = [String]()
        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/"),
                  seen.insert(path).inserted,
                  fileManager.isExecutableFile(atPath: path)
            else { continue }
            paths.append(path)
        }
        return paths
    }

    private static func isPlainExecutableName(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\") && !value.contains(where: \.isWhitespace)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

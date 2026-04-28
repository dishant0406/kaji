import Foundation

enum AIProviderExecutableLocator {
    static func isInstalled(
        executableNames: [String],
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> Bool {
        executableNames.contains { name in
            guard let path = resolvePath(
                for: name,
                env: env,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
            else {
                return false
            }
            return fileManager.isExecutableFile(atPath: path)
        }
    }

    static func resolvePath(
        for executableName: String,
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> String? {
        for path in candidatePaths(for: executableName, env: env, homeDirectory: homeDirectory, fileManager: fileManager) {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return shellResolvedPath(for: executableName)
    }

    static func candidatePaths(
        for executableName: String,
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager
    ) -> [String] {
        var paths = [String]()
        let pathVariable = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        for directory in pathVariable where !directory.isEmpty {
            paths.append((directory as NSString).appendingPathComponent(executableName))
        }

        let staticDirectories = [
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/.volta/bin",
            "\(homeDirectory)/.asdf/shims",
            "\(homeDirectory)/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
        for directory in staticDirectories {
            paths.append((directory as NSString).appendingPathComponent(executableName))
        }

        let nvmVersionsDirectory = "\(homeDirectory)/.nvm/versions/node"
        if let versionDirectories = try? fileManager.contentsOfDirectory(
            atPath: nvmVersionsDirectory
        ) {
            for version in versionDirectories {
                let path = "\(nvmVersionsDirectory)/\(version)/bin/\(executableName)"
                paths.append(path)
            }
        }

        var deduped = [String]()
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            deduped.append(path)
        }
        return deduped
    }

    private static func shellResolvedPath(for executableName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "command -v -- \(shellQuoted(executableName))"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

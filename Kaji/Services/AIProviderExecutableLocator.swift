import Foundation

enum AIProviderExecutableLocator {
    static func isInstalled(
        executableNames: [String],
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        extraDirectories: [String] = []
    ) -> Bool {
        executableNames.contains { name in
            guard let path = resolvePath(
                for: name,
                env: env,
                homeDirectory: homeDirectory,
                fileManager: fileManager,
                extraDirectories: extraDirectories
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
        fileManager: FileManager = .default,
        extraDirectories: [String] = []
    ) -> String? {
        for path in candidatePaths(
            for: executableName,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            extraDirectories: extraDirectories
        )
            where fileManager.isExecutableFile(atPath: path)
        {
            return path
        }
        return shellResolvedPath(for: executableName)
    }

    static func candidatePaths(
        for executableName: String,
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        extraDirectories: [String] = []
    ) -> [String] {
        var paths = nvmExecutablePaths(
            for: executableName,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        let pathVariable = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        for directory in pathVariable where !directory.isEmpty {
            paths.append((directory as NSString).appendingPathComponent(executableName))
        }

        let staticDirectories = extraDirectories.map { directory in
            directory.hasPrefix("/") ? directory : "\(homeDirectory)/\(directory)"
        } + [
            "\(homeDirectory)/.opencode/bin",
            "\(homeDirectory)/.bun/bin",
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

        return dedupe(paths)
    }

    private static func nvmExecutablePaths(
        for executableName: String,
        homeDirectory: String,
        fileManager: FileManager
    ) -> [String] {
        let nvmVersionsDirectory = "\(homeDirectory)/.nvm/versions/node"
        if let versionDirectories = try? fileManager.contentsOfDirectory(
            atPath: nvmVersionsDirectory
        ) {
            return versionDirectories
                .sorted { compareNodeVersion($0, $1) == .orderedDescending }
                .map { "\(nvmVersionsDirectory)/\($0)/bin/\(executableName)" }
        }
        return []
    }

    private static func compareNodeVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionNumbers(lhs)
        let right = versionNumbers(rhs)
        let count = max(left.count, right.count)
        for index in 0 ..< count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue > rightValue { return .orderedDescending }
            if leftValue < rightValue { return .orderedAscending }
        }
        return lhs.compare(rhs)
    }

    private static func versionNumbers(_ value: String) -> [Int] {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    private static func dedupe(_ paths: [String]) -> [String] {
        var deduped = [String]()
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            deduped.append(path)
        }
        return deduped
    }

    static func preferredRealPath(
        for executableName: String,
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        excluding directory: URL
    ) -> String? {
        let shimPath = directory.path + "/"
        return candidatePaths(
            for: executableName,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).first {
            !$0.hasPrefix(shimPath) && fileManager.isExecutableFile(atPath: $0)
        }
    }

    private static func shellResolvedPath(for executableName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "whence -p -- \(shellQuoted(executableName))"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        let timedOut = finished.wait(timeout: .now() + 5) == .timedOut
        if timedOut {
            process.terminate()
            process.waitUntilExit()
            return nil
        }

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

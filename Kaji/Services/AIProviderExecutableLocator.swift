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
        extraDirectories: [String] = [],
        excluding directory: URL? = nil
    ) -> String? {
        if let managedPath = managedPath(
            for: executableName,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            directories: extraDirectories
        ) {
            return managedPath
        }
        return ShellExecutableResolver.resolvePaths(
            for: executableName,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).first { path in
            guard let directory else { return true }
            return !path.hasPrefix(directory.path + "/")
        }
    }

    private static func managedPath(
        for executableName: String,
        homeDirectory: String,
        fileManager: FileManager,
        directories: [String]
    ) -> String? {
        for directory in directories {
            let expanded = directory.replacingOccurrences(of: "~", with: homeDirectory, options: .anchored)
            let path = (expanded as NSString).appendingPathComponent(executableName)
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func preferredRealPath(
        for executableName: String,
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager,
        excluding directory: URL
    ) -> String? {
        resolvePath(
            for: executableName,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            excluding: directory
        )
    }
}

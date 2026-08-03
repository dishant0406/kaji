import Foundation

enum KajiCodeRuntimeSource: String, Equatable {
    case developerOverride
    case managed
    case path
}

struct KajiCodeRuntimeResolution: Equatable {
    let binaryURL: URL
    let source: KajiCodeRuntimeSource
    let version: String?
}

enum KajiCodeRuntimeLocator {
    static func resolve(
        configuredCommand: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> KajiCodeRuntimeResolution? {
        if let override = executableOverride(env: env, fileManager: fileManager) {
            return .init(binaryURL: override, source: .developerOverride, version: nil)
        }
        if let configured = executableFromConfiguredCommand(
            configuredCommand,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ) {
            return .init(binaryURL: configured, source: .path, version: nil)
        }
        if let manifest = KajiCodeInstallStore.read(env: env, fileManager: fileManager),
           manifest.platform == KajiCodePlatform.current,
           let binaryURL = KajiCodePaths.binaryURL(for: manifest, env: env),
           isExecutableRegularFile(binaryURL, fileManager: fileManager)
        {
            return .init(binaryURL: binaryURL, source: .managed, version: manifest.activeVersion)
        }
        if let binaryURL = executableOnPath(env: env, homeDirectory: homeDirectory, fileManager: fileManager) {
            return .init(binaryURL: binaryURL, source: .path, version: nil)
        }
        return nil
    }

    static func launchCommand(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> String {
        resolve(env: env, homeDirectory: homeDirectory, fileManager: fileManager)
            .map { ShellEscaper.escape($0.binaryURL.path) } ?? "kajicode"
    }

    private static func executableOverride(env: [String: String], fileManager: FileManager) -> URL? {
        guard let value = env[KajiCodePaths.devBinaryKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        let binaryURL = URL(fileURLWithPath: value)
        return isExecutableRegularFile(binaryURL, fileManager: fileManager) ? binaryURL : nil
    }

    private static func executableFromConfiguredCommand(
        _ command: String?,
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager
    ) -> URL? {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty,
              command != "kajicode"
        else { return nil }
        return CLILauncherCommandResolver.resolvedExecutableURL(
            in: command,
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
    }

    private static func executableOnPath(
        env: [String: String],
        homeDirectory: String,
        fileManager: FileManager
    ) -> URL? {
        AIProviderExecutableLocator.resolvePath(
            for: "kajicode",
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ).map(URL.init(fileURLWithPath:))
    }

    private static func isExecutableRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.isExecutableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

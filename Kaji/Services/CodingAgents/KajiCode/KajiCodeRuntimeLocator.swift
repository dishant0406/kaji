import Foundation

enum KajiCodeRuntimeSource: String, Equatable {
    case developerOverride
    case managed
    case bundled
    case path
}

struct KajiCodeRuntimeResolution: Equatable {
    let binaryURL: URL
    let source: KajiCodeRuntimeSource
    let version: String?
}

enum KajiCodeRuntimeLocator {
    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> KajiCodeRuntimeResolution? {
        if let override = executableOverride(env: env, fileManager: fileManager) {
            return .init(binaryURL: override, source: .developerOverride, version: nil)
        }
        if let manifest = KajiCodeInstallStore.read(env: env, fileManager: fileManager),
           fileManager.isExecutableFile(atPath: manifest.binaryPath)
        {
            return .init(
                binaryURL: URL(fileURLWithPath: manifest.binaryPath),
                source: .managed,
                version: manifest.activeVersion
            )
        }
        if let bundled = KajiCodePaths.bundledBinaryURL(fileManager: fileManager) {
            return .init(binaryURL: bundled, source: .bundled, version: nil)
        }
        if let path = AIProviderExecutableLocator.resolvePath(
            for: "kajicode",
            env: env,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ) {
            return .init(binaryURL: URL(fileURLWithPath: path), source: .path, version: nil)
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
              !value.isEmpty,
              fileManager.isExecutableFile(atPath: value)
        else { return nil }
        return URL(fileURLWithPath: value)
    }
}

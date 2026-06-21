import Foundation

enum KajiAgentRuntimeLocator {
    private static let cache = KajiAgentRuntimeLocatorCache()
    private static let bunLookupTTL: TimeInterval = 30

    static func resolveLaunch(
        projectPath: String?,
        sessionDirectory: String? = nil,
        approvalMode: String = KajiAgentPermissionMode.readAllow.rawValue,
        noSession: Bool = false,
        noLSP: Bool = false,
        noTools: Bool = false
    ) -> KajiAgentLaunchResolution {
        guard let script = sourceScriptURL() ?? bundledRuntimeScript() else { return .missingRuntime }
        switch bunLookup() {
        case let .found(path, _):
            return .ready(KajiAgentLaunch(
                arguments: [path, script.url.path] + launchArguments(
                    projectPath: projectPath,
                    sessionDirectory: sessionDirectory,
                    approvalMode: approvalMode,
                    flags: KajiAgentRuntimeLaunchFlags(noSession: noSession, noLSP: noLSP, noTools: noTools)
                ),
                directory: script.directory
            ))
        case .missing:
            return .missingBun
        case let .unsupported(version):
            return .unsupportedBunVersion(version)
        }
    }

    static func sourceLaunch(
        projectPath: String?,
        sessionDirectory: String? = nil,
        approvalMode: String = KajiAgentPermissionMode.readAllow.rawValue,
        noSession: Bool = false,
        noLSP: Bool = false,
        noTools: Bool = false
    ) -> KajiAgentLaunch? {
        guard let script = sourceScriptURL(), case let .found(path, _) = bunLookup() else { return nil }
        return KajiAgentLaunch(
            arguments: [path, script.url.path] + launchArguments(
                projectPath: projectPath,
                sessionDirectory: sessionDirectory,
                approvalMode: approvalMode,
                flags: KajiAgentRuntimeLaunchFlags(noSession: noSession, noLSP: noLSP, noTools: noTools)
            ),
            directory: script.directory
        )
    }

    static func bundledScriptURL() -> URL? {
        bundledRuntimeScript()?.url
    }

    static func bundledLaunch(
        projectPath: String?,
        sessionDirectory: String? = nil,
        approvalMode: String = KajiAgentPermissionMode.readAllow.rawValue,
        noSession: Bool = false,
        noLSP: Bool = false,
        noTools: Bool = false
    ) -> KajiAgentLaunch? {
        guard let script = bundledRuntimeScript(), case let .found(path, _) = bunLookup() else { return nil }
        return KajiAgentLaunch(
            arguments: [path, script.url.path] + launchArguments(
                projectPath: projectPath,
                sessionDirectory: sessionDirectory,
                approvalMode: approvalMode,
                flags: KajiAgentRuntimeLaunchFlags(noSession: noSession, noLSP: noLSP, noTools: noTools)
            ),
            directory: script.directory
        )
    }

    static func bunExecutablePath() -> String? {
        guard case let .found(path, _) = bunLookup() else { return nil }
        return path
    }

    static func clearCache() {
        cache.clear()
    }

    private static func bunLookup() -> KajiAgentBunLookupResult {
        if let cached = cache.bunLookup(ttl: bunLookupTTL) { return cached }
        guard let path = AIProviderExecutableLocator.resolvePath(for: "bun") else {
            cache.updateBunLookup(.missing)
            return .missing
        }
        let version = KajiAgentBunVersion.read(at: path)
        guard version.supportsKajiAgentRuntime else {
            let result = KajiAgentBunLookupResult.unsupported(version.rawValue)
            cache.updateBunLookup(result)
            return result
        }
        let result = KajiAgentBunLookupResult.found(path: path, version: version.rawValue)
        cache.updateBunLookup(result)
        return result
    }

    private static func launchArguments(
        projectPath: String?,
        sessionDirectory: String?,
        approvalMode: String,
        flags: KajiAgentRuntimeLaunchFlags
    ) -> [String] {
        var args = ["--approval-mode", approvalMode]
        if let projectPath, !projectPath.isEmpty {
            args.append(contentsOf: ["--cwd", projectPath])
        }
        if let sessionDirectory, !sessionDirectory.isEmpty {
            args.append(contentsOf: ["--session-dir", sessionDirectory])
        }
        if flags.noSession { args.append("--no-session") }
        if flags.noLSP { args.append("--no-lsp") }
        if flags.noTools { args.append("--no-tools") }
        return args
    }

    private static func sourceScriptURL() -> KajiAgentRuntimeScript? {
        guard let root = projectRoot() else { return nil }
        let runtimeRoot = root.appending(path: "KajiAgentRuntime")
        let script = runtimeRoot.appending(path: "src/kaji-rpc.ts")
        guard FileManager.default.fileExists(atPath: script.path) else { return nil }
        return KajiAgentRuntimeScript(url: script, directory: runtimeRoot)
    }

    private static func bundledRuntimeScript() -> KajiAgentRuntimeScript? {
        guard let url = bundledResourceURL(named: "kaji-agent-runtime") ?? bundledDevScriptURL() else { return nil }
        return KajiAgentRuntimeScript(url: url, directory: nil)
    }

    private static func bundledResourceURL(named name: String) -> URL? {
        Bundle.appResources.url(forResource: name, withExtension: "mjs", subdirectory: "KajiAgentRuntime")
            ?? Bundle.appResources.url(forResource: name, withExtension: "mjs")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "KajiAgentRuntime")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "Kaji_Kaji.bundle/KajiAgentRuntime")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "Kaji_Kaji.bundle")
    }

    private static func bundledDevScriptURL() -> URL? {
        guard let root = projectRoot() else { return nil }
        let url = root.appending(path: "Kaji/Resources/KajiAgentRuntime/kaji-agent-runtime.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func projectRoot() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            ProcessInfo.processInfo.environment["KAJI_PROJECT_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            Bundle.main.executableURL?.deletingLastPathComponent(),
            Bundle.main.bundleURL,
        ].compactMap(\.self)

        for candidate in candidates {
            if let root = containingProjectRoot(startingAt: candidate, fileManager: fileManager) {
                return root
            }
        }
        return nil
    }

    private static func containingProjectRoot(startingAt url: URL, fileManager: FileManager) -> URL? {
        var cursor = url.standardizedFileURL
        while cursor.path != "/" {
            if fileManager.fileExists(atPath: cursor.appending(path: "Package.swift").path),
               fileManager.fileExists(atPath: cursor.appending(path: "KajiAgentRuntime/src/kaji-rpc.ts").path)
            {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }
}

private struct KajiAgentRuntimeLaunchFlags {
    let noSession: Bool
    let noLSP: Bool
    let noTools: Bool
}

struct KajiAgentLaunch: Equatable {
    let arguments: [String]
    let directory: URL?

    var signature: String {
        ([directory?.path ?? ""] + arguments).joined(separator: "\u{1f}")
    }
}

struct KajiAgentRuntimeScript {
    let url: URL
    let directory: URL?
}

enum KajiAgentLaunchResolution: Equatable {
    case ready(KajiAgentLaunch)
    case missingRuntime
    case missingBun
    case unsupportedBunVersion(String?)

    var readiness: KajiAgentReadiness {
        switch self {
        case .ready:
            .ready
        case .missingRuntime:
            .missingRuntime
        case .missingBun:
            .missingBun
        case let .unsupportedBunVersion(version):
            .unsupportedBunVersion(version)
        }
    }
}

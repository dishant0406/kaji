import Foundation

enum KajiAgentRuntimeLocator {
    private static let cache = KajiAgentRuntimeLocatorCache()
    private static let bunLookupTTL: TimeInterval = 30

    static func sourceLaunch(projectPath: String?, sessionDirectory: String? = nil, approvalMode: String = KajiAgentPermissionMode.readAllow.rawValue) -> KajiAgentLaunch? {
        guard let root = projectRoot() else { return nil }
        let runtimeRoot = root.appending(path: "KajiAgentRuntime")
        let script = runtimeRoot.appending(path: "src/kaji-rpc.ts")
        guard FileManager.default.fileExists(atPath: script.path), let bun = bunExecutablePath() else { return nil }
        return KajiAgentLaunch(arguments: [bun, script.path] + launchArguments(projectPath: projectPath, sessionDirectory: sessionDirectory, approvalMode: approvalMode), directory: runtimeRoot)
    }

    static func bundledScriptURL() -> URL? {
        bundledResourceURL(named: "kaji-agent-runtime")
            ?? bundledDevScriptURL()
    }

    static func bundledLaunch(projectPath: String?, sessionDirectory: String? = nil, approvalMode: String = KajiAgentPermissionMode.readAllow.rawValue) -> KajiAgentLaunch? {
        guard let script = bundledScriptURL(), let bun = bunExecutablePath() else { return nil }
        return KajiAgentLaunch(arguments: [bun, script.path] + launchArguments(projectPath: projectPath, sessionDirectory: sessionDirectory, approvalMode: approvalMode), directory: nil)
    }

    static func bunExecutablePath() -> String? {
        if let cached = cache.bunExecutablePath(ttl: bunLookupTTL) { return cached }
        guard let path = AIProviderExecutableLocator.resolvePath(for: "bun"), bunVersion(at: path).supportsKajiAgentRuntime else {
            cache.updateBunExecutablePath(nil)
            return nil
        }
        cache.updateBunExecutablePath(path)
        return path
    }

    static func clearCache() {
        cache.clear()
    }

    private static func launchArguments(projectPath: String?, sessionDirectory: String?, approvalMode: String) -> [String] {
        var args = ["--approval-mode", approvalMode]
        if let projectPath, !projectPath.isEmpty {
            args.append(contentsOf: ["--cwd", projectPath])
        }
        if let sessionDirectory, !sessionDirectory.isEmpty {
            args.append(contentsOf: ["--session-dir", sessionDirectory])
        }
        return args
    }

    private static func bunVersion(at path: String) -> KajiAgentBunVersion {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return KajiAgentBunVersion()
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return KajiAgentBunVersion() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return KajiAgentBunVersion(String(data: data, encoding: .utf8) ?? "")
    }

    private static func bundledResourceURL(named name: String) -> URL? {
        Bundle.appResources.url(forResource: name, withExtension: "mjs", subdirectory: "KajiAgentRuntime")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "KajiAgentRuntime")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "Kaji_Kaji.bundle/KajiAgentRuntime")
    }

    private static func bundledDevScriptURL() -> URL? {
        guard let root = projectRoot() else { return nil }
        let url = root
            .appending(path: "Kaji/Resources/KajiAgentRuntime/kaji-agent-runtime.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func projectRoot() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            ProcessInfo.processInfo.environment["KAJI_PROJECT_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            Bundle.main.executableURL?.deletingLastPathComponent(),
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
            if fileManager.fileExists(atPath: cursor.appending(path: "Kaji/Info.plist").path),
               fileManager.fileExists(atPath: cursor.appending(path: "KajiAgentRuntime/src/kaji-rpc.ts").path)
            {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }
}

private final class KajiAgentRuntimeLocatorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedBunExecutablePath: String?
    private var cachedBunLookupDate: Date?

    func bunExecutablePath(ttl: TimeInterval) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let cachedBunExecutablePath,
              let cachedBunLookupDate,
              Date().timeIntervalSince(cachedBunLookupDate) < ttl
        else { return nil }
        return cachedBunExecutablePath
    }

    func updateBunExecutablePath(_ path: String?) {
        lock.lock()
        cachedBunExecutablePath = path
        cachedBunLookupDate = Date()
        lock.unlock()
    }

    func clear() {
        lock.lock()
        cachedBunExecutablePath = nil
        cachedBunLookupDate = nil
        lock.unlock()
    }
}

struct KajiAgentLaunch {
    let arguments: [String]
    let directory: URL?
}

private struct KajiAgentBunVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ value: String = "") {
        let parts = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "v \n\t"))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        major = parts.indices.contains(0) ? parts[0] : 0
        minor = parts.indices.contains(1) ? parts[1] : 0
        patch = parts.indices.contains(2) ? parts[2] : 0
    }

    var supportsKajiAgentRuntime: Bool {
        self >= KajiAgentBunVersion("1.3.14")
    }

    static func < (lhs: KajiAgentBunVersion, rhs: KajiAgentBunVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

import Foundation

enum ParentAgentRuntimeLocator {
    static func sourceLaunch() -> ParentAgentLaunch? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtimeRoot = root.appending(path: "KajiParentAgentRuntime")
        let script = runtimeRoot.appending(path: "src/main.ts")
        let tsx = runtimeRoot.appending(path: "node_modules/.bin/tsx")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: tsx.path)
        else { return nil }
        return ParentAgentLaunch(arguments: [tsx.path, script.path], directory: runtimeRoot)
    }

    static func sourceOAuthLaunch(providerID: String) -> ParentAgentLaunch? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtimeRoot = root.appending(path: "KajiParentAgentRuntime")
        let script = runtimeRoot.appending(path: "src/oauth-login.ts")
        let tsx = runtimeRoot.appending(path: "node_modules/.bin/tsx")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: tsx.path)
        else { return nil }
        return ParentAgentLaunch(arguments: [tsx.path, script.path, providerID], directory: runtimeRoot)
    }

    static func bundledScriptURL() -> URL? {
        bundledResourceURL(named: "kaji-agent")
            ?? bundledDevScriptURL()
    }

    static func bundledLaunch() -> ParentAgentLaunch? {
        guard let script = bundledScriptURL(), let node = nodeExecutablePath() else { return nil }
        return ParentAgentLaunch(arguments: [node, script.path], directory: nil)
    }

    static func bundledOAuthLaunch(providerID: String) -> ParentAgentLaunch? {
        guard let script = bundledResourceURL(named: "oauth-login")
            ?? bundledDevOAuthScriptURL(),
            let node = nodeExecutablePath()
        else { return nil }
        return ParentAgentLaunch(arguments: [node, script.path, providerID], directory: nil)
    }

    static func nodeExecutablePath() -> String? {
        guard let path = AIProviderExecutableLocator.resolvePath(for: "node"),
              nodeVersion(at: path).supportsParentAgentRuntime
        else { return nil }
        return path
    }

    private static func nodeVersion(at path: String) -> ParentAgentNodeVersion {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ParentAgentNodeVersion()
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return ParentAgentNodeVersion() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8) ?? ""
        return ParentAgentNodeVersion(value)
    }

    private static func bundledResourceURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "mjs", subdirectory: "pi")
            ?? Bundle.module.url(forResource: name, withExtension: "mjs")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "pi")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "Kaji_Kaji.bundle/pi")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "Kaji_Kaji.bundle")
    }

    private static func bundledDevScriptURL() -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Kaji/Resources/pi/kaji-agent.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func bundledDevOAuthScriptURL() -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Kaji/Resources/pi/oauth-login.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

struct ParentAgentLaunch {
    let arguments: [String]
    let directory: URL?
}

private struct ParentAgentNodeVersion: Comparable {
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

    var supportsParentAgentRuntime: Bool {
        self >= ParentAgentNodeVersion("22.19.0")
    }

    static func < (lhs: ParentAgentNodeVersion, rhs: ParentAgentNodeVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

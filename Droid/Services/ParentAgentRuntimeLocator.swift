import Foundation

enum ParentAgentRuntimeLocator {
    static func sourceLaunch() -> ParentAgentLaunch? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let piRoot = root.appending(path: "Vendor/pi-mono")
        let script = piRoot.appending(path: "packages/droid-agent/src/main.ts")
        let tsx = piRoot.appending(path: "node_modules/.bin/tsx")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: tsx.path)
        else { return nil }
        return ParentAgentLaunch(arguments: [tsx.path, script.path], directory: piRoot)
    }

    static func sourceOAuthLaunch(providerID: String) -> ParentAgentLaunch? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let piRoot = root.appending(path: "Vendor/pi-mono")
        let script = piRoot.appending(path: "packages/droid-agent/src/oauth-login.ts")
        let tsx = piRoot.appending(path: "node_modules/.bin/tsx")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: tsx.path)
        else { return nil }
        return ParentAgentLaunch(arguments: [tsx.path, script.path, providerID], directory: piRoot)
    }

    static func bundledScriptURL() -> URL? {
        bundledResourceURL(named: "droid-agent")
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
        AIProviderExecutableLocator.resolvePath(for: "node")
    }

    private static func bundledResourceURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "mjs", subdirectory: "pi")
            ?? Bundle.module.url(forResource: name, withExtension: "mjs")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "pi")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "Droid_Droid.bundle/pi")
            ?? Bundle.main.url(forResource: name, withExtension: "mjs", subdirectory: "Droid_Droid.bundle")
    }

    private static func bundledDevScriptURL() -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Droid/Resources/pi/droid-agent.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func bundledDevOAuthScriptURL() -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Droid/Resources/pi/oauth-login.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

struct ParentAgentLaunch {
    let arguments: [String]
    let directory: URL?
}

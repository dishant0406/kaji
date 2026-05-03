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

    static func bundledScriptURL() -> URL? {
        Bundle.module.url(forResource: "droid-agent", withExtension: "mjs", subdirectory: "pi")
            ?? Bundle.main.url(forResource: "droid-agent", withExtension: "mjs", subdirectory: "pi")
            ?? bundledDevScriptURL()
    }

    static func bundledLaunch() -> ParentAgentLaunch? {
        guard let script = bundledScriptURL() else { return nil }
        return ParentAgentLaunch(arguments: ["node", script.path], directory: nil)
    }

    static func nodeExecutablePath() -> String? {
        var candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { String($0) + "/node" })
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func bundledDevScriptURL() -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Droid/Resources/pi/droid-agent.mjs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

struct ParentAgentLaunch {
    let arguments: [String]
    let directory: URL?
}

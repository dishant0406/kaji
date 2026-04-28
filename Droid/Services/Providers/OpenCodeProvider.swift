import Foundation

struct OpenCodeProvider: AIProviderIntegration {
    let id = "opencode"
    let displayName = "OpenCode"
    let socketTypeKey = "opencode"
    let iconName = "opencode"
    let executableNames = ["opencode"]

    private static let pluginFileName = "droid-notify.js"
    private static let pluginScriptName = "opencode-droid-plugin.js"

    func isToolInstalled() -> Bool {
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/.opencode/bin/opencode",
            "\(home)/.local/bin/opencode",
            "/usr/local/bin/opencode",
            "/opt/homebrew/bin/opencode",
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func install(hookScriptPath: String) throws {
        guard let sourcePlugin = Self.findPluginSource(near: hookScriptPath) else { return }
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePlugin))

        for pluginPath in Self.pluginPaths() {
            if FileManager.default.fileExists(atPath: pluginPath),
               let existingData = try? Data(contentsOf: URL(fileURLWithPath: pluginPath)),
               existingData == sourceData
            {
                continue
            }

            let pluginsDir = (pluginPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: pluginsDir, withIntermediateDirectories: true)
            let dest = URL(fileURLWithPath: pluginPath)
            if FileManager.default.fileExists(atPath: pluginPath) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePlugin), to: dest)
        }
    }

    func uninstall() throws {
        for pluginPath in Self.pluginPaths() where FileManager.default.fileExists(atPath: pluginPath) {
            try FileManager.default.removeItem(atPath: pluginPath)
        }
    }

    private static func findPluginSource(near hookScriptPath: String) -> String? {
        if let bundled = DroidNotificationHooks.scriptPath(named: "opencode-droid-plugin", extension: "js") {
            return bundled
        }

        let hookDir = (hookScriptPath as NSString).deletingLastPathComponent
        let candidate = (hookDir as NSString).appendingPathComponent(pluginScriptName)
        guard FileManager.default.fileExists(atPath: candidate) else { return nil }
        return candidate
    }

    static func pluginPaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "\(homeDirectory)/.config/opencode/plugins/\(pluginFileName)",
            "\(homeDirectory)/.opencode/plugins/\(pluginFileName)",
        ]
    }
}

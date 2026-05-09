import Foundation

enum DroidBrowserAgentScripts {
    static let mcpScriptName = "droid-browser-mcp"

    static func install(into directory: URL, fileManager: FileManager = .default) -> URL? {
        guard let source = DroidNotificationHooks.scriptPath(
            named: "droid-browser-mcp",
            extension: "js",
            subdirectory: "CodingAgents/Browser"
        )
        else { return nil }
        let destination = directory.appendingPathComponent(mcpScriptName)
        do {
            let sourceData = try Data(contentsOf: URL(fileURLWithPath: source))
            if !fileManager.fileExists(atPath: destination.path) || (try? Data(contentsOf: destination)) != sourceData {
                try sourceData.write(to: destination, options: .atomic)
            }
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
            return destination
        } catch {
            return nil
        }
    }
}

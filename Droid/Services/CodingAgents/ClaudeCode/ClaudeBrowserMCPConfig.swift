import Foundation

enum ClaudeBrowserMCPConfig {
    static func projectConfig(for descriptor: DroidBrowserMCPServerDescriptor) -> [String: Any] {
        [
            "mcpServers": [
                descriptor.name: [
                    "type": "stdio",
                    "command": descriptor.command,
                    "args": descriptor.arguments,
                    "env": descriptor.environment,
                ],
            ],
        ]
    }

    static func write(
        descriptor: DroidBrowserMCPServerDescriptor,
        homeDirectory: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let directory = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".droid", isDirectory: true)
            .appendingPathComponent("agent-configs", isDirectory: true)
        let file = directory.appendingPathComponent("claude-browser-mcp.json")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: projectConfig(for: descriptor), options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return file
        } catch {
            return nil
        }
    }
}

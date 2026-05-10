import Foundation

enum OpenCodeBrowserMCPConfig {
    static func config(for descriptor: DroidBrowserMCPServerDescriptor) -> [String: Any] {
        [
            "mcp": [
                descriptor.name: [
                    "type": "local",
                    "command": [descriptor.command] + descriptor.arguments,
                    "enabled": true,
                    "environment": descriptor.environment,
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
        let file = directory.appendingPathComponent("opencode-browser-mcp.json")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: config(for: descriptor), options: [.prettyPrinted, .sortedKeys])
            try data.write(to: file, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return file
        } catch {
            return nil
        }
    }
}

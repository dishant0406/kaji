import Foundation

@MainActor
enum CodingAgentBrowserEnvironment {
    static func variables(
        browserValues: [(key: String, value: String)],
        homeDirectory: String,
        fileManager: FileManager
    ) -> [(key: String, value: String)] {
        guard let descriptor = descriptor(browserValues) else { return [] }
        var values = [(key: "KAJI_CODEX_BROWSER_MCP_ARGS", value: CodexBrowserMCPConfig.shellArguments(for: descriptor))]
        values.append(contentsOf: configValue(
            key: "KAJI_CLAUDE_BROWSER_MCP_CONFIG",
            file: ClaudeBrowserMCPConfig.write(
                descriptor: descriptor,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        ))
        values.append(contentsOf: configValue(
            key: "KAJI_OPENCODE_BROWSER_MCP_CONFIG",
            file: OpenCodeBrowserMCPConfig.write(
                descriptor: descriptor,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        ))
        values.append(contentsOf: configValue(
            key: "KAJI_PI_BROWSER_MCP_CONFIG",
            file: PiBrowserMCPConfig.write(
                descriptor: descriptor,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        ))
        return values
    }

    static func descriptor(_ values: [(key: String, value: String)]) -> KajiBrowserMCPServerDescriptor? {
        let environment = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0.value) })
        guard let command = environment["KAJI_BROWSER_MCP_COMMAND"] else { return nil }
        return KajiBrowserMCPServerDescriptor(
            name: "kaji-browser",
            command: command,
            arguments: [],
            environment: environment.filter { key, _ in key.hasPrefix("KAJI_BROWSER_") }
        )
    }

    static func writeInstalledConfigs(homeDirectory: String, fileManager: FileManager = .default) {
        guard let descriptor = installedDescriptor(homeDirectory: homeDirectory, fileManager: fileManager) else { return }
        _ = ClaudeBrowserMCPConfig.write(descriptor: descriptor, homeDirectory: homeDirectory, fileManager: fileManager)
        _ = OpenCodeBrowserMCPConfig.write(descriptor: descriptor, homeDirectory: homeDirectory, fileManager: fileManager)
        _ = PiBrowserMCPConfig.write(descriptor: descriptor, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    static func installedDescriptor(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> KajiBrowserMCPServerDescriptor? {
        let command = CodingAgentShimInstaller.browserMCPURL(homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: command.path) else { return nil }
        return KajiBrowserMCPServerDescriptor(name: "kaji-browser", command: command.path, arguments: [], environment: [:])
    }

    static func removeConfigs(homeDirectory: String, fileManager: FileManager = .default) {
        let directory = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".kaji", isDirectory: true)
            .appendingPathComponent("agent-configs", isDirectory: true)
        for name in ["claude-browser-mcp.json", "opencode-browser-mcp.json", "pi-browser-mcp.json"] {
            let file = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: file.path) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private static func configValue(key: String, file: URL?) -> [(key: String, value: String)] {
        guard let file else { return [] }
        return [(key: key, value: file.path)]
    }
}

import Foundation

@MainActor
enum CodingAgentBrowserEnvironment {
    static func variables(
        browserValues: [(key: String, value: String)],
        homeDirectory: String,
        fileManager: FileManager
    ) -> [(key: String, value: String)] {
        guard let descriptor = descriptor(browserValues) else { return [] }
        var values = [(key: "DROID_CODEX_BROWSER_MCP_ARGS", value: CodexBrowserMCPConfig.shellArguments(for: descriptor))]
        values.append(contentsOf: configValue(
            key: "DROID_CLAUDE_BROWSER_MCP_CONFIG",
            file: ClaudeBrowserMCPConfig.write(
                descriptor: descriptor,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        ))
        values.append(contentsOf: configValue(
            key: "DROID_OPENCODE_BROWSER_MCP_CONFIG",
            file: OpenCodeBrowserMCPConfig.write(
                descriptor: descriptor,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        ))
        values.append(contentsOf: configValue(
            key: "DROID_PI_BROWSER_MCP_CONFIG",
            file: PiBrowserMCPConfig.write(
                descriptor: descriptor,
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        ))
        return values
    }

    static func descriptor(_ values: [(key: String, value: String)]) -> DroidBrowserMCPServerDescriptor? {
        let environment = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0.value) })
        guard let command = environment["DROID_BROWSER_MCP_COMMAND"] else { return nil }
        return DroidBrowserMCPServerDescriptor(
            name: "droid-browser",
            command: command,
            arguments: [],
            environment: environment.filter { key, _ in key.hasPrefix("DROID_BROWSER_") }
        )
    }

    private static func configValue(key: String, file: URL?) -> [(key: String, value: String)] {
        guard let file else { return [] }
        return [(key: key, value: file.path)]
    }
}

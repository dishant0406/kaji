import Foundation

enum AIGatewayClaudeCodeRouterGatewayEntryWriter {
    static func write(fileManager: FileManager = .default) throws {
        let directory = AIGatewayClaudeCodeRouterPaths.pluginsDirectory()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = AIGatewayClaudeCodeRouterPaths.gatewayEntryURL()
        try source.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static let source = #"""
    const fs = require("node:fs");
    const path = require("node:path");

    const configPath = process.env.GATEWAY_CONFIG_PATH;
    const pluginPath = process.env.KAJI_CCR_OPENAI_RESPONSES_PLUGIN;
    if (configPath && pluginPath && fs.existsSync(configPath)) {
      const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
      const plugins = Array.isArray(config.plugins) ? config.plugins : [];
      if (!plugins.some(plugin => plugin && plugin.key === "kaji-openai-responses")) {
        config.plugins = [...plugins, { enabled: true, key: "kaji-openai-responses", modulePath: pluginPath }];
        fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
      }
    }

    const packageDir = process.env.KAJI_CCR_PACKAGE_DIR;
    if (!packageDir) throw new Error("KAJI_CCR_PACKAGE_DIR is missing.");
    require(path.join(packageDir, "node_modules", "@the-next-ai", "ai-gateway"));
    """#
}

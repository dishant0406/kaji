import Foundation

enum AIGatewayClaudeCodeRouterPaths {
    static let packageName = "@musistudio/claude-code-router"
    static let packageVersion = "3.0.1"
    static let nodeVersion = "v22.15.0"

    static func rootDirectory() -> URL {
        AIGatewayStoragePaths.supportDirectory().appendingPathComponent("claude-code-router", isDirectory: true)
    }

    static func toolsDirectory() -> URL {
        rootDirectory().appendingPathComponent("tools", isDirectory: true)
    }

    static func packageDirectory(version: String = packageVersion) -> URL {
        toolsDirectory().appendingPathComponent("ccr-\(version)", isDirectory: true)
    }

    static func commandURL(version: String = packageVersion) -> URL {
        packageDirectory(version: version)
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent(".bin", isDirectory: true)
            .appendingPathComponent("ccr")
    }

    static func manifestURL() -> URL {
        rootDirectory().appendingPathComponent("install-manifest.json")
    }

    static func runtimeHome() -> URL {
        rootDirectory().appendingPathComponent("home", isDirectory: true)
    }

    static func appData() -> URL {
        rootDirectory().appendingPathComponent("app-data", isDirectory: true)
    }

    static func userData() -> URL {
        rootDirectory().appendingPathComponent("user-data", isDirectory: true)
    }

    static func configDirectory() -> URL {
        runtimeHome().appendingPathComponent(".claude-code-router", isDirectory: true)
    }

    static func configURL() -> URL {
        configDirectory().appendingPathComponent("config.json")
    }

    static func pluginsDirectory() -> URL {
        configDirectory().appendingPathComponent("plugins", isDirectory: true)
    }

    static func openAIResponsesPluginURL() -> URL {
        pluginsDirectory().appendingPathComponent("kaji-openai-responses.cjs")
    }

    static func gatewayEntryURL() -> URL {
        pluginsDirectory().appendingPathComponent("kaji-gateway-entry.cjs")
    }
}

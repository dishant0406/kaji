import Foundation

@MainActor
enum KajiBrowserAgentEnvironment {
    static func variables(
        sessionID: String,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        browserEnabled: Bool = BrowserExtensionPreferences.isEnabled,
        unsafeToolsEnabled: Bool = BrowserExtensionPreferences.allowsUnsafeTools
    ) -> [(key: String, value: String)] {
        guard browserEnabled else { return [] }
        guard let state = KajiBrowserControlBroker.shared.ensureStarted(sessionID: sessionID) else { return [] }
        var values = [
            (key: "KAJI_BROWSER_BROKER_URL", value: state.brokerURL),
            (key: "KAJI_BROWSER_MCP_TOKEN", value: state.token),
            (key: "KAJI_BROWSER_SESSION_ID", value: sessionID),
        ]
        if let cdpURL = state.cdpURL, let cdpPort = state.cdpPort {
            values.append((key: "KAJI_BROWSER_CDP_URL", value: cdpURL))
            values.append((key: "KAJI_BROWSER_CDP_PORT", value: String(cdpPort)))
        }
        if let command = mcpCommand(homeDirectory: homeDirectory, fileManager: fileManager) {
            values.append((key: "KAJI_BROWSER_MCP_COMMAND", value: command))
        }
        if unsafeToolsEnabled {
            values.append((key: "KAJI_BROWSER_ALLOW_UNSAFE_TOOLS", value: "1"))
        }
        return values
    }

    static func dictionary(
        sessionID: String,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        browserEnabled: Bool = BrowserExtensionPreferences.isEnabled,
        unsafeToolsEnabled: Bool = BrowserExtensionPreferences.allowsUnsafeTools
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: variables(
            sessionID: sessionID,
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            browserEnabled: browserEnabled,
            unsafeToolsEnabled: unsafeToolsEnabled
        ).map { ($0.key, $0.value) })
    }

    private static func mcpCommand(homeDirectory: String, fileManager: FileManager) -> String? {
        let url = CodingAgentShimInstaller.browserMCPURL(homeDirectory: homeDirectory)
        return fileManager.fileExists(atPath: url.path) ? url.path : nil
    }
}

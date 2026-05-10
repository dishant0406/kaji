import Foundation

@MainActor
enum DroidBrowserAgentEnvironment {
    static func variables(
        sessionID: String,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        browserEnabled: Bool = BrowserExtensionPreferences.isEnabled,
        unsafeToolsEnabled: Bool = BrowserExtensionPreferences.allowsUnsafeTools
    ) -> [(key: String, value: String)] {
        guard browserEnabled else { return [] }
        guard let state = DroidBrowserControlBroker.shared.ensureStarted(sessionID: sessionID) else { return [] }
        var values = [
            (key: "DROID_BROWSER_BROKER_URL", value: state.brokerURL),
            (key: "DROID_BROWSER_MCP_TOKEN", value: state.token),
            (key: "DROID_BROWSER_SESSION_ID", value: sessionID),
        ]
        if let cdpURL = state.cdpURL, let cdpPort = state.cdpPort {
            values.append((key: "DROID_BROWSER_CDP_URL", value: cdpURL))
            values.append((key: "DROID_BROWSER_CDP_PORT", value: String(cdpPort)))
        }
        if let command = mcpCommand(homeDirectory: homeDirectory, fileManager: fileManager) {
            values.append((key: "DROID_BROWSER_MCP_COMMAND", value: command))
        }
        if unsafeToolsEnabled {
            values.append((key: "DROID_BROWSER_ALLOW_UNSAFE_TOOLS", value: "1"))
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

import Foundation

enum DroidBrowserMCPResourceLocator {
    static func scriptPath(fileManager: FileManager = .default, projectRoot: URL? = nil) -> String? {
        candidates(fileManager: fileManager, projectRoot: projectRoot)
            .first { fileManager.fileExists(atPath: $0.path) }?
            .path
    }

    private static func candidates(fileManager: FileManager, projectRoot: URL?) -> [URL] {
        var urls: [URL] = []
        if let projectRoot {
            urls.append(projectRoot.appendingPathComponent("Droid/Resources/CodingAgents/Browser/droid-browser-mcp.js"))
        }
        appendBundleCandidates(to: &urls)
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Droid/Resources/CodingAgents/Browser/droid-browser-mcp.js"))
        return urls
    }

    private static func appendBundleCandidates(to urls: inout [URL]) {
        if let url = Bundle.module.url(forResource: "droid-browser-mcp", withExtension: "js") {
            urls.append(url)
        }
        if let url = Bundle.module.url(
            forResource: "droid-browser-mcp",
            withExtension: "js",
            subdirectory: "CodingAgents/Browser"
        ) {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Droid_Droid.bundle/droid-browser-mcp.js"))
            urls.append(resourceURL.appendingPathComponent("droid-browser-mcp.js"))
        }
    }
}

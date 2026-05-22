import Foundation

enum KajiBrowserMCPResourceLocator {
    static let supportFileNames = [
        "kaji-tools.js",
        "framing.js",
        "main.js",
        "playwright-client.js",
        "playwright-tool-cache.js",
        "playwright-tools.js",
        "results.js",
        "safety.js",
        "session.js",
    ]

    static func scriptPath(fileManager: FileManager = .default, projectRoot: URL? = nil) -> String? {
        candidates(fileManager: fileManager, projectRoot: projectRoot)
            .first { fileManager.fileExists(atPath: $0.path) }?
            .path
    }

    static func supportDirectory(fileManager: FileManager = .default, projectRoot: URL? = nil) -> URL? {
        supportCandidates(fileManager: fileManager, projectRoot: projectRoot)
            .first { isDirectory($0, fileManager: fileManager) }
    }

    static func supportFiles(fileManager: FileManager = .default, projectRoot: URL? = nil) -> [URL] {
        supportFileNames.compactMap { name in
            supportFileCandidates(name: name, fileManager: fileManager, projectRoot: projectRoot)
                .first { fileManager.fileExists(atPath: $0.path) }
        }
    }

    private static func candidates(fileManager: FileManager, projectRoot: URL?) -> [URL] {
        var urls: [URL] = []
        if let projectRoot {
            urls.append(projectRoot.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser-mcp.js"))
        }
        appendBundleCandidates(to: &urls)
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser-mcp.js"))
        return urls
    }

    private static func appendBundleCandidates(to urls: inout [URL]) {
        if let url = Bundle.appResources.url(forResource: "kaji-browser-mcp", withExtension: "js") {
            urls.append(url)
        }
        if let url = Bundle.appResources.url(
            forResource: "kaji-browser-mcp",
            withExtension: "js",
            subdirectory: "CodingAgents/Browser"
        ) {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/kaji-browser-mcp.js"))
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/CodingAgents/Browser/kaji-browser-mcp.js"))
            urls.append(resourceURL.appendingPathComponent("kaji-browser-mcp.js"))
        }
    }

    private static func supportCandidates(fileManager: FileManager, projectRoot: URL?) -> [URL] {
        var urls: [URL] = []
        if let projectRoot {
            urls.append(projectRoot.appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser", isDirectory: true))
        }
        if let url = Bundle.appResources.url(forResource: "kaji-browser", withExtension: nil, subdirectory: "CodingAgents/Browser") {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/kaji-browser", isDirectory: true))
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/CodingAgents/Browser/kaji-browser", isDirectory: true))
            urls.append(resourceURL.appendingPathComponent("kaji-browser", isDirectory: true))
        }
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Kaji/Resources/CodingAgents/Browser/kaji-browser", isDirectory: true))
        return urls
    }

    private static func supportFileCandidates(name: String, fileManager: FileManager, projectRoot: URL?) -> [URL] {
        var urls = supportCandidates(fileManager: fileManager, projectRoot: projectRoot).map { $0.appendingPathComponent(name) }
        let basename = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        if let url = Bundle.appResources.url(forResource: basename, withExtension: "js") {
            urls.append(url)
        }
        if let url = Bundle.appResources.url(forResource: basename, withExtension: "js", subdirectory: "CodingAgents/Browser/kaji-browser") {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/\(name)"))
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/kaji-browser/\(name)"))
            urls.append(resourceURL.appendingPathComponent(name))
        }
        return urls
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

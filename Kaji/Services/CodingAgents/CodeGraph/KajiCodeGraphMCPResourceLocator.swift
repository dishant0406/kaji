import Foundation

enum KajiCodeGraphMCPResourceLocator {
    static let supportFileNames = [
        "codegraph-tools.js",
        "codegraph-framing.js",
        "graph-query.js",
        "graph-store.js",
        "codegraph-main.js",
        "codegraph-results.js",
        "codegraph-tool-catalog.js",
    ]

    static func scriptPath(fileManager: FileManager = .default, projectRoot: URL? = nil) -> String? {
        scriptCandidates(fileManager: fileManager, projectRoot: projectRoot)
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

    private static func scriptCandidates(fileManager: FileManager, projectRoot: URL?) -> [URL] {
        var urls = [URL]()
        if let projectRoot {
            urls.append(projectRoot.appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph-mcp.js"))
        }
        appendBundleScriptCandidates(to: &urls)
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph-mcp.js"))
        return urls
    }

    private static func appendBundleScriptCandidates(to urls: inout [URL]) {
        if let url = Bundle.appResources.url(forResource: "kaji-codegraph-mcp", withExtension: "js") {
            urls.append(url)
        }
        if let url = Bundle.appResources.url(
            forResource: "kaji-codegraph-mcp",
            withExtension: "js",
            subdirectory: "CodingAgents/CodeGraph"
        ) {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/kaji-codegraph-mcp.js"))
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/CodingAgents/CodeGraph/kaji-codegraph-mcp.js"))
            urls.append(resourceURL.appendingPathComponent("kaji-codegraph-mcp.js"))
        }
    }

    private static func supportCandidates(fileManager: FileManager, projectRoot: URL?) -> [URL] {
        var urls = [URL]()
        if let projectRoot {
            urls.append(projectRoot.appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph", isDirectory: true))
        }
        if let url = Bundle.appResources.url(forResource: "kaji-codegraph", withExtension: nil, subdirectory: "CodingAgents/CodeGraph") {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/kaji-codegraph", isDirectory: true))
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/CodingAgents/CodeGraph/kaji-codegraph", isDirectory: true))
            urls.append(resourceURL.appendingPathComponent("kaji-codegraph", isDirectory: true))
        }
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Kaji/Resources/CodingAgents/CodeGraph/kaji-codegraph", isDirectory: true))
        return urls
    }

    private static func supportFileCandidates(name: String, fileManager: FileManager, projectRoot: URL?) -> [URL] {
        var urls = supportCandidates(fileManager: fileManager, projectRoot: projectRoot).map { $0.appendingPathComponent(name) }
        let basename = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        if let url = Bundle.appResources.url(forResource: basename, withExtension: "js") {
            urls.append(url)
        }
        if let url = Bundle.appResources.url(
            forResource: basename,
            withExtension: "js",
            subdirectory: "CodingAgents/CodeGraph/kaji-codegraph"
        ) {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/\(name)"))
            urls.append(resourceURL.appendingPathComponent("Kaji_Kaji.bundle/kaji-codegraph/\(name)"))
            urls.append(resourceURL.appendingPathComponent(name))
        }
        return urls
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

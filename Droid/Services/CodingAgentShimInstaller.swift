import Foundation

enum CodingAgentShimInstaller {
    static func directory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".droid", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static func install(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default,
        installBrowserMCP: Bool = BrowserExtensionPreferences.isEnabled
    ) -> URL? {
        let directory = directory(homeDirectory: homeDirectory)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            for shim in CodingAgentShimScript.all {
                let url = directory.appendingPathComponent(shim.name)
                let data = Data(shim.content.utf8)
                if !fileManager.fileExists(atPath: url.path) || (try? Data(contentsOf: url)) != data {
                    try data.write(to: url, options: .atomic)
                }
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            try syncBrowserMCP(into: directory, enabled: installBrowserMCP, fileManager: fileManager)
            return directory
        } catch {
            return nil
        }
    }

    static func browserMCPURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        directory(homeDirectory: homeDirectory).appendingPathComponent("droid-browser-mcp")
    }

    private static func syncBrowserMCP(into directory: URL, enabled: Bool, fileManager: FileManager) throws {
        let url = directory.appendingPathComponent("droid-browser-mcp")
        guard enabled else {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }
        guard let source = DroidBrowserMCPResourceLocator.scriptPath(fileManager: fileManager) else {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: source))
        if !fileManager.fileExists(atPath: url.path) || (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}

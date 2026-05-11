import Foundation

enum CodingAgentShimInstaller {
    static func directory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".kaji", isDirectory: true)
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
        directory(homeDirectory: homeDirectory).appendingPathComponent("kaji-browser-mcp")
    }

    private static func syncBrowserMCP(into directory: URL, enabled: Bool, fileManager: FileManager) throws {
        let url = directory.appendingPathComponent("kaji-browser-mcp")
        let support = directory.appendingPathComponent("kaji-browser", isDirectory: true)
        guard enabled else {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            if fileManager.fileExists(atPath: support.path) {
                try fileManager.removeItem(at: support)
            }
            return
        }
        guard let source = KajiBrowserMCPResourceLocator.scriptPath(fileManager: fileManager) else {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            if fileManager.fileExists(atPath: support.path) {
                try fileManager.removeItem(at: support)
            }
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: source))
        if !fileManager.fileExists(atPath: url.path) || (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try syncBrowserMCPSupport(into: support, fileManager: fileManager)
    }

    private static func syncBrowserMCPSupport(into support: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: support.path) {
            try fileManager.removeItem(at: support)
        }
        if let source = KajiBrowserMCPResourceLocator.supportDirectory(fileManager: fileManager) {
            try fileManager.copyItem(at: source, to: support)
        } else {
            let files = KajiBrowserMCPResourceLocator.supportFiles(fileManager: fileManager)
            guard !files.isEmpty else { return }
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            for file in files {
                try fileManager.copyItem(at: file, to: support.appendingPathComponent(file.lastPathComponent))
            }
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
    }
}

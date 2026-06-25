import Foundation

enum KajiBrowserMCPBinaryInstaller {
    static func directory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".kaji", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static func commandURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        directory(homeDirectory: homeDirectory).appendingPathComponent("kaji-browser-mcp")
    }

    static func install(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = directory(homeDirectory: homeDirectory)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try syncCommand(into: directory, fileManager: fileManager)
        return commandURL(homeDirectory: homeDirectory)
    }

    static func remove(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) throws {
        let directory = directory(homeDirectory: homeDirectory)
        let command = commandURL(homeDirectory: homeDirectory)
        let support = directory.appendingPathComponent("kaji-browser", isDirectory: true)
        if fileManager.fileExists(atPath: command.path) {
            try fileManager.removeItem(at: command)
        }
        if fileManager.fileExists(atPath: support.path) {
            try fileManager.removeItem(at: support)
        }
    }

    static func isInstalled(homeDirectory: String = NSHomeDirectory(), fileManager: FileManager = .default) -> Bool {
        let command = commandURL(homeDirectory: homeDirectory)
        let supportMain = directory(homeDirectory: homeDirectory).appendingPathComponent("kaji-browser/main.js")
        return fileManager.isExecutableFile(atPath: command.path) && fileManager.fileExists(atPath: supportMain.path)
    }

    private static func syncCommand(into directory: URL, fileManager: FileManager) throws {
        guard let source = KajiBrowserMCPResourceLocator.scriptPath(fileManager: fileManager) else {
            throw KajiBrowserMCPBinaryInstallerError.missingResource
        }
        let command = directory.appendingPathComponent("kaji-browser-mcp")
        let data = try Data(contentsOf: URL(fileURLWithPath: source))
        if !fileManager.fileExists(atPath: command.path) || (try? Data(contentsOf: command)) != data {
            try data.write(to: command, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
        try syncSupport(into: directory.appendingPathComponent("kaji-browser", isDirectory: true), fileManager: fileManager)
    }

    private static func syncSupport(into support: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: support.path) {
            try fileManager.removeItem(at: support)
        }
        if let source = KajiBrowserMCPResourceLocator.supportDirectory(fileManager: fileManager) {
            try fileManager.copyItem(at: source, to: support)
        } else {
            let files = KajiBrowserMCPResourceLocator.supportFiles(fileManager: fileManager)
            guard !files.isEmpty else { throw KajiBrowserMCPBinaryInstallerError.missingResource }
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            for file in files {
                try fileManager.copyItem(at: file, to: support.appendingPathComponent(file.lastPathComponent))
            }
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
    }
}

enum KajiBrowserMCPBinaryInstallerError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        "Kaji Browser MCP resources are missing."
    }
}

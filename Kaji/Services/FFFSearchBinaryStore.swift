import Foundation

enum FFFSearchBinaryStore {
    static let version = "0.8.1"

    static func libraryURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try installDirectory(fileManager: fileManager)
        let url = directory.appendingPathComponent("libfff_c.dylib")
        if fileManager.fileExists(atPath: url.path) { return url }
        try installLibrary(to: url, fileManager: fileManager)
        return url
    }

    static func installDirectory(fileManager: FileManager = .default) throws -> URL {
        let directory = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("Search", isDirectory: true)
            .appendingPathComponent("FFF", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent(architecturePackageName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func installLibrary(to url: URL, fileManager: FileManager) throws {
        let package = "@ff-labs/\(architecturePackageName)@\(version)"
        let existingArchives = Set((try? fileManager.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )) ?? [])
        try ProcessExecutor.runSync(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["npm", "pack", package, "--silent", "--pack-destination", url.deletingLastPathComponent().path],
            currentDirectoryURL: url.deletingLastPathComponent()
        )
        let archives = try fileManager.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        guard let archive = archives.first(where: { $0.pathExtension == "tgz" && !existingArchives.contains($0) })
            ?? archives.first(where: { $0.pathExtension == "tgz" })
        else {
            throw FFFSearchError.processFailed("FFF npm package archive was not created")
        }
        try ProcessExecutor.runSync(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archive.path, "--strip-components", "1", "package/libfff_c.dylib"],
            currentDirectoryURL: url.deletingLastPathComponent()
        )
    }

    private static var architecturePackageName: String {
        #if arch(arm64)
        "fff-bin-darwin-arm64"
        #else
        "fff-bin-darwin-x64"
        #endif
    }
}

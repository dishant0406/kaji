import CryptoKit
import Foundation

enum FFFSearchBinaryStore {
    static let version = "0.10.0"

    static func libraryURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try installDirectory(fileManager: fileManager)
        let url = directory.appendingPathComponent("libfff_c.dylib")
        if try hasExpectedLibraryDigest(url: url, fileManager: fileManager) {
            return url
        }
        try installLibrary(to: url, fileManager: fileManager)
        guard try hasExpectedLibraryDigest(url: url, fileManager: fileManager) else {
            throw FFFSearchError.processFailed("FFF library integrity verification failed")
        }
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
        let directory = url.deletingLastPathComponent()
        let staging = directory.appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        try ProcessExecutor.runSync(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "npm",
                "pack",
                "@ff-labs/\(architecturePackageName)@\(version)",
                "--ignore-scripts",
                "--silent",
                "--pack-destination",
                staging.path,
            ],
            currentDirectoryURL: staging
        )
        let archives = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.fileSizeKey])
        guard archives.count == 1, let archive = archives.first, archive.pathExtension == "tgz" else {
            throw FFFSearchError.processFailed("FFF npm package archive was not created")
        }
        let values = try archive.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0, size <= 100 * 1024 * 1024 else {
            throw FFFSearchError.processFailed("FFF npm package archive has an invalid size")
        }
        let archiveData = try Data(contentsOf: archive, options: .mappedIfSafe)
        let integrity = Data(SHA512.hash(data: archiveData)).base64EncodedString()
        guard integrity == expectedArchiveIntegrity else {
            throw FFFSearchError.processFailed("FFF npm package integrity verification failed")
        }
        try ProcessExecutor.runSync(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archive.path, "--strip-components", "1", "package/libfff_c.dylib"],
            currentDirectoryURL: staging
        )
        let extracted = staging.appendingPathComponent("libfff_c.dylib")
        guard try hasExpectedLibraryDigest(url: extracted, fileManager: fileManager) else {
            throw FFFSearchError.processFailed("FFF extracted library integrity verification failed")
        }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: extracted, to: url)
    }

    private static func hasExpectedLibraryDigest(url: URL, fileManager: FileManager) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expectedLibrarySHA256
    }

    private static var architecturePackageName: String {
        #if arch(arm64)
        "fff-bin-darwin-arm64"
        #else
        "fff-bin-darwin-x64"
        #endif
    }

    private static var expectedArchiveIntegrity: String {
        #if arch(arm64)
        "czH/JVKXdzovByBowzHFI7E72V9usIx7uAWypRcN6KRkaTLL/xU7Eo2GF1NFAlaP3t1elQNMQj502NL/WyXdpw=="
        #else
        "eKGYWeuj8/dwdxv/qtxSiZusUpZ/rvdI8RGYGeCxJO9AQzFUNxmfXZMgtprCOKwIMwealC1S9dK9PugcSyMSKw=="
        #endif
    }

    private static var expectedLibrarySHA256: String {
        #if arch(arm64)
        "20d4968edb1453bf5c766060e75c23281a592907e569bcae22ffb68a662d5999"
        #else
        "e665da5e361c1ebd06d612576ef0b4da7c58b81e00375bc361a17703f343cac4"
        #endif
    }
}

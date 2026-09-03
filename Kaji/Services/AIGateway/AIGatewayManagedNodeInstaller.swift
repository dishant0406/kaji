import CryptoKit
import Foundation

enum AIGatewayManagedNodeInstaller {
    static func install(fileManager: FileManager = .default) throws -> AIGatewayNodeRuntime {
        if let runtime = AIGatewayNodeRuntimeResolver.resolve(fileManager: fileManager) {
            return runtime
        }
        let archive = try downloadArchive(fileManager: fileManager)
        try verifyArchive(archive)
        let runtimeDirectory = managedRuntimeDirectory()
        let staging = AIGatewayClaudeCodeRouterPaths.toolsDirectory()
            .appendingPathComponent("node-staging-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: runtimeDirectory.path) {
            try fileManager.removeItem(at: runtimeDirectory)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = try AIGatewayProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archive.path, "-C", staging.path, "--strip-components", "1"],
            timeout: 120
        )
        guard result.exitCode == 0 else { throw AIGatewayManagedNodeInstallerError.extractFailed(result.output) }
        try fileManager.moveItem(at: staging, to: runtimeDirectory)
        guard let runtime = AIGatewayNodeRuntimeResolver.resolve(fileManager: fileManager) else {
            throw AIGatewayManagedNodeInstallerError.runtimeMissing
        }
        return runtime
    }

    static func managedRuntimeDirectory() -> URL {
        AIGatewayClaudeCodeRouterPaths.toolsDirectory()
            .appendingPathComponent("node-\(AIGatewayClaudeCodeRouterPaths.nodeVersion)", isDirectory: true)
    }

    static func archiveURL(architecture: String = systemArchitecture()) throws -> URL {
        try endpointURL("node-\(AIGatewayClaudeCodeRouterPaths.nodeVersion)-darwin-\(architecture).tar.gz")
    }

    private static func downloadArchive(fileManager: FileManager) throws -> URL {
        let directory = AIGatewayClaudeCodeRouterPaths.toolsDirectory()
            .appendingPathComponent("downloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let source = try archiveURL()
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }
        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return destination
    }

    private static func verifyArchive(_ archive: URL) throws {
        let sums = try String(contentsOf: endpointURL("SHASUMS256.txt"), encoding: .utf8)
        guard let expected = sums.split(separator: "\n").first(where: { $0.contains(archive.lastPathComponent) })?
            .split(separator: " ").first.map(String.init)
        else { throw AIGatewayManagedNodeInstallerError.checksumMissing }
        let data = try Data(contentsOf: archive)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw AIGatewayManagedNodeInstallerError.checksumMismatch }
    }

    private static func endpointURL(_ file: String) throws -> URL {
        guard let url = URL(string: "https://nodejs.org/dist/\(AIGatewayClaudeCodeRouterPaths.nodeVersion)/\(file)") else {
            throw AIGatewayManagedNodeInstallerError.invalidURL
        }
        return url
    }

    private static func systemArchitecture() -> String {
        #if arch(arm64)
        "arm64"
        #else
        "x64"
        #endif
    }
}

enum AIGatewayManagedNodeInstallerError: LocalizedError {
    case checksumMismatch
    case checksumMissing
    case extractFailed(String)
    case invalidURL
    case runtimeMissing

    var errorDescription: String? {
        switch self {
        case .checksumMismatch: "Managed Node.js download failed checksum verification."
        case .checksumMissing: "Managed Node.js checksum could not be found."
        case let .extractFailed(output): output.isEmpty ? "Managed Node.js extraction failed." : output
        case .invalidURL: "Managed Node.js download URL is invalid."
        case .runtimeMissing: "Managed Node.js runtime was installed but could not be resolved."
        }
    }
}

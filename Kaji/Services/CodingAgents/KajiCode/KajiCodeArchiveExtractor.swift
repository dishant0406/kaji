import Foundation

enum KajiCodeArchiveExtractor {
    static func extract(
        archiveURL: URL,
        destination: URL,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let entries = try await tarEntries(archiveURL: archiveURL)
        guard entries.contains("kajicode") else { throw KajiCodeInstallError.missingBinary }
        guard entries.allSatisfy(isSafeEntry) else { throw KajiCodeInstallError.unsafeArchive }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = try AIGatewayProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archiveURL.path, "-C", destination.path],
            timeout: 60
        )
        guard result.exitCode == 0 else { throw KajiCodeInstallError.extractFailed(result.output) }
        let binary = destination.appendingPathComponent("kajicode")
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        return binary
    }

    private static func tarEntries(archiveURL: URL) async throws -> [String] {
        try await GitProcessRunner.offMainThrowing {
            let result = try AIGatewayProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-tzf", archiveURL.path],
                timeout: 30
            )
            guard result.exitCode == 0 else { throw KajiCodeInstallError.extractFailed(result.output) }
            return result.stdout.split(separator: "\n").map(String.init)
        }
    }

    private static func isSafeEntry(_ entry: String) -> Bool {
        !entry.isEmpty &&
            !entry.hasPrefix("/") &&
            !entry.split(separator: "/").contains("..") &&
            !entry.contains("\\")
    }
}

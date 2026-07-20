import Foundation

enum KajiCodeArchiveExtractor {
    static func extract(
        archiveURL: URL,
        destination: URL,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let entries = try await tarEntries(archiveURL: archiveURL)
        guard entries.allSatisfy(isSafeEntry) else { throw KajiCodeInstallError.unsafeArchive }
        guard entries.map(normalizedEntry).contains("kajicode") else { throw KajiCodeInstallError.missingBinary }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw KajiCodeInstallError.extractFailed("Extraction destination already exists.")
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

    private static func normalizedEntry(_ entry: String) -> String {
        entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
    }
}

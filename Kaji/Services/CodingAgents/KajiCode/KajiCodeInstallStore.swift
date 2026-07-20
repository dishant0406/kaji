import Foundation

enum KajiCodeInstallStore {
    static func read(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> KajiCodeInstallManifest? {
        let url = KajiCodePaths.manifestURL(env: env)
        guard fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(KajiCodeInstallManifest.self, from: data)
    }

    static func write(
        _ manifest: KajiCodeInstallManifest,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        let url = KajiCodePaths.manifestURL(env: env)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func remove(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        let url = KajiCodePaths.manifestURL(env: env)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

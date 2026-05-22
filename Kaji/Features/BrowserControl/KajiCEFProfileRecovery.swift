import Foundation

enum KajiCEFProfileRecovery {
    private static let markerName = ".kaji-cef-starting"
    private static let staleNames = [
        "SingletonCookie",
        "SingletonLock",
        "SingletonSocket",
    ]

    static func prepareProfile(at profileURL: URL, fileManager: FileManager = .default) throws -> URL {
        if fileManager.fileExists(atPath: markerURL(for: profileURL).path) {
            return try quarantine(profileURL, fileManager: fileManager)
        }

        try fileManager.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try removeStaleFiles(in: profileURL, fileManager: fileManager)
        try Data().write(to: markerURL(for: profileURL), options: .atomic)
        return profileURL
    }

    static func markStarted(profileURL: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: markerURL(for: profileURL))
    }

    private static func quarantine(_ profileURL: URL, fileManager: FileManager) throws -> URL {
        let quarantineURL = profileURL.deletingLastPathComponent()
            .appendingPathComponent("CEFProfile.quarantined-\(timestamp())", isDirectory: true)

        try? fileManager.removeItem(at: markerURL(for: profileURL))
        if fileManager.fileExists(atPath: profileURL.path) {
            try fileManager.moveItem(at: profileURL, to: quarantineURL)
        }
        try fileManager.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try Data().write(to: markerURL(for: profileURL), options: .atomic)
        return profileURL
    }

    private static func removeStaleFiles(in profileURL: URL, fileManager: FileManager) throws {
        for name in staleNames {
            let url = profileURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private static func markerURL(for profileURL: URL) -> URL {
        profileURL.appendingPathComponent(markerName)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

import Foundation

enum KajiCEFProfileRecovery {
    private static let markerName = ".kaji-cef-starting"
    private static let runtimeActiveName = ".kaji-cef-runtime-active"
    private static let cleanShutdownName = ".kaji-cef-clean-shutdown"
    private static let staleNames = [
        "SingletonCookie",
        "SingletonLock",
        "SingletonSocket",
    ]

    static func prepareProfile(at profileURL: URL, fileManager: FileManager = .default) throws -> URL {
        if shouldQuarantine(profileURL, fileManager: fileManager) {
            return try quarantine(profileURL, fileManager: fileManager)
        }

        try fileManager.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try removeStaleFiles(in: profileURL, fileManager: fileManager)
        try? fileManager.removeItem(at: markerURL(for: profileURL, name: cleanShutdownName))
        try Data().write(to: markerURL(for: profileURL), options: .atomic)
        return profileURL
    }

    static func markStarted(profileURL: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: markerURL(for: profileURL))
        try? Data().write(to: markerURL(for: profileURL, name: runtimeActiveName), options: .atomic)
        try? fileManager.removeItem(at: markerURL(for: profileURL, name: cleanShutdownName))
    }

    static func markCleanShutdown(profileURL: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: markerURL(for: profileURL))
        try? fileManager.removeItem(at: markerURL(for: profileURL, name: runtimeActiveName))
        try? Data().write(to: markerURL(for: profileURL, name: cleanShutdownName), options: .atomic)
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

    private static func shouldQuarantine(_ profileURL: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: markerURL(for: profileURL).path) { return true }
        let active = markerURL(for: profileURL, name: runtimeActiveName)
        let clean = markerURL(for: profileURL, name: cleanShutdownName)
        return fileManager.fileExists(atPath: active.path) && !fileManager.fileExists(atPath: clean.path)
    }

    private static func removeStaleFiles(in profileURL: URL, fileManager: FileManager) throws {
        for name in staleNames {
            let url = profileURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private static func markerURL(for profileURL: URL) -> URL {
        markerURL(for: profileURL, name: markerName)
    }

    private static func markerURL(for profileURL: URL, name: String) -> URL {
        profileURL.appendingPathComponent(name)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

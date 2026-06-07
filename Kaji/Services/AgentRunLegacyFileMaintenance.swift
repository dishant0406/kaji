import Foundation

struct AgentRunLegacyFileMaintenance {
    let maxBackupCount: Int

    init(maxBackupCount: Int = 1) {
        self.maxBackupCount = maxBackupCount
    }

    func finalize(legacyURL: URL, now: Date = Date()) throws {
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try archiveOrRemoveLegacyFile(legacyURL: legacyURL, now: now)
        }
        try pruneBackups(legacyURL: legacyURL)
    }

    private func archiveOrRemoveLegacyFile(legacyURL: URL, now: Date) throws {
        if backupURLs(legacyURL: legacyURL).isEmpty {
            try FileManager.default.moveItem(at: legacyURL, to: backupURL(legacyURL: legacyURL, now: now))
            return
        }
        try FileManager.default.removeItem(at: legacyURL)
    }

    private func pruneBackups(legacyURL: URL) throws {
        let backups = backupURLs(legacyURL: legacyURL).sorted { lhs, rhs in
            modificationDate(lhs) > modificationDate(rhs)
        }
        for url in backups.dropFirst(maxBackupCount) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func backupURLs(legacyURL: URL) -> [URL] {
        let directory = legacyURL.deletingLastPathComponent()
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return children.filter { $0.lastPathComponent.hasPrefix("agent-runs.legacy-") && $0.pathExtension == "json" }
    }

    private func backupURL(legacyURL: URL, now: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        return legacyURL.deletingLastPathComponent().appendingPathComponent("agent-runs.legacy-\(stamp).json")
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

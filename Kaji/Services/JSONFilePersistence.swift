import Foundation

enum KajiFileStorage {
    private static let appSupportOverrideKey = "KAJI_APP_SUPPORT_DIR"

    static func fileURL(filename: String) -> URL {
        let dir = appSupportDirectory()
        return dir.appendingPathComponent(filename)
    }

    static func appSupportDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment[appSupportOverrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return dir
        }

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        else {
            fatalError("Application Support directory unavailable")
        }
        let dir = appSupport.appendingPathComponent("Kaji", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    static func worktreeRoot(forProjectID projectID: UUID) -> URL {
        let dir = appSupportDirectory()
            .appendingPathComponent("worktree-checkouts", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    static func worktreeDirectory(forProjectID projectID: UUID, name: String) -> URL {
        worktreeRoot(forProjectID: projectID).appendingPathComponent(name, isDirectory: true)
    }
}

import Foundation
import os

private let logger = Logger(subsystem: "app.droid", category: "DroidNotificationHooks")

enum DroidNotificationHooks {
    private static let hookClientName = "DroidHookClient"

    static var hookClientPath: String? {
        if let bundled = findBundledExecutable(hookClientName) {
            return bundled
        }

        if let sibling = findSiblingExecutable(hookClientName) {
            return sibling
        }

        return nil
    }

    private static func findBundledExecutable(_ name: String) -> String? {
        let candidates = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(name)"),
        ]

        for case let url? in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }

        return nil
    }

    private static func findSiblingExecutable(_ name: String) -> String? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        let candidate = execURL.deletingLastPathComponent().appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate.path
    }

    static func scriptPath(named name: String, extension ext: String) -> String? {
        if let bundled = findBundledScript(name, extension: ext) {
            return bundled
        }

        let devPath = findDevScriptPath(name + "." + ext)
        if let devPath, FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        return nil
    }

    private static func findBundledScript(_ name: String, extension ext: String) -> String? {
        guard let url = Bundle.appResources.url(forResource: name, withExtension: ext) else {
            return nil
        }

        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        if !FileManager.default.isExecutableFile(atPath: path) {
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            } catch {
                logger.error("Failed to set executable permission on \(path): \(error.localizedDescription)")
                return nil
            }
        }

        return path
    }

    private static func findDevScriptPath(_ fileName: String) -> String? {
        guard let execURL = Bundle.main.executableURL else { return nil }
        var dir = execURL.deletingLastPathComponent()
        for _ in 0 ..< 10 {
            let candidate = dir.appendingPathComponent("scripts/\(fileName)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                if !FileManager.default.isExecutableFile(atPath: candidate.path) {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)
                }
                return candidate.path
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else { break }
            dir = parent
        }
        return nil
    }
}

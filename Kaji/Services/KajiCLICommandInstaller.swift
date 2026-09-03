import Foundation

enum KajiCLICommandInstallState: Equatable {
    case installed
    case missing
    case needsRepair(String)
}

struct KajiCLICommandInstallResult: Equatable {
    let state: KajiCLICommandInstallState
    let message: String
}

enum KajiCLICommandInstaller {
    typealias PrivilegedInstall = (URL, URL) -> Bool
    typealias PrivilegedRemove = (URL) -> Bool

    static func commandURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent(".kaji/bin/kaji")
    }

    static func globalLinkURL() -> URL {
        URL(fileURLWithPath: "/usr/local/bin/kaji")
    }

    static func state(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        linkURL: URL = globalLinkURL(),
        fileManager: FileManager = .default
    ) -> KajiCLICommandInstallState {
        let command = commandURL(homeDirectory: homeDirectory)
        guard managedScriptExists(at: command, fileManager: fileManager) else { return .missing }
        return linkState(command: command, link: linkURL, fileManager: fileManager)
    }

    static func install(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        linkURL: URL = globalLinkURL(),
        fileManager: FileManager = .default,
        privilegedInstall: PrivilegedInstall = KajiCLIPrivilegedLinkInstaller.install
    ) -> KajiCLICommandInstallResult {
        let command = commandURL(homeDirectory: homeDirectory)
        do {
            try writeCommand(to: command, fileManager: fileManager)
        } catch {
            return KajiCLICommandInstallResult(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
        if ensureLink(command: command, link: linkURL, fileManager: fileManager, privilegedInstall: privilegedInstall) {
            return KajiCLICommandInstallResult(state: .installed, message: "Installed kaji command.")
        }
        let current = state(homeDirectory: homeDirectory, linkURL: linkURL, fileManager: fileManager)
        return KajiCLICommandInstallResult(state: current, message: message(for: current))
    }

    static func uninstall(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        linkURL: URL = globalLinkURL(),
        fileManager: FileManager = .default,
        privilegedRemove: PrivilegedRemove = KajiCLIPrivilegedLinkInstaller.remove
    ) -> KajiCLICommandInstallResult {
        let command = commandURL(homeDirectory: homeDirectory)
        removeManagedLink(command: command, link: linkURL, fileManager: fileManager, privilegedRemove: privilegedRemove)
        if managedScriptExists(at: command, fileManager: fileManager) {
            try? fileManager.removeItem(at: command)
        }
        let current = state(homeDirectory: homeDirectory, linkURL: linkURL, fileManager: fileManager)
        return KajiCLICommandInstallResult(
            state: current,
            message: current == .missing ? "Uninstalled kaji command." : message(for: current)
        )
    }

    private static func writeCommand(to url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let content = KajiCLICommandScriptFactory.script()
        if (try? String(contentsOf: url, encoding: .utf8)) != content {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func ensureLink(
        command: URL,
        link: URL,
        fileManager: FileManager,
        privilegedInstall: PrivilegedInstall
    ) -> Bool {
        switch linkState(command: command, link: link, fileManager: fileManager) {
        case .installed:
            return true
        case let .needsRepair(message) where message.contains("already exists"):
            return false
        default:
            break
        }
        try? fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try? fileManager.removeItem(at: link)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: command)
            return true
        } catch {
            return privilegedInstall(command, link)
        }
    }

    private static func removeManagedLink(
        command: URL,
        link: URL,
        fileManager: FileManager,
        privilegedRemove: PrivilegedRemove
    ) {
        guard linkPointsToCommand(link: link, command: command, fileManager: fileManager) || managedScriptExists(
            at: link,
            fileManager: fileManager
        )
        else { return }
        do {
            try fileManager.removeItem(at: link)
        } catch {
            _ = privilegedRemove(link)
        }
    }

    private static func linkState(command: URL, link: URL, fileManager: FileManager) -> KajiCLICommandInstallState {
        guard fileManager.fileExists(atPath: link.path) else { return .missing }
        if linkPointsToCommand(link: link, command: command, fileManager: fileManager) {
            return .installed
        }
        if managedScriptExists(at: link, fileManager: fileManager) {
            return .installed
        }
        return .needsRepair("/usr/local/bin/kaji already exists and is not managed by Kaji.")
    }

    private static func linkPointsToCommand(link: URL, command: URL, fileManager: FileManager) -> Bool {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL.path == command
            .standardizedFileURL.path
    }

    private static func managedScriptExists(at url: URL, fileManager: FileManager) -> Bool {
        (try? String(contentsOf: url, encoding: .utf8)) == KajiCLICommandScriptFactory.script()
    }

    private static func message(for state: KajiCLICommandInstallState) -> String {
        switch state {
        case .installed:
            "Installed kaji command."
        case .missing:
            "kaji command is not installed."
        case let .needsRepair(message):
            message
        }
    }
}

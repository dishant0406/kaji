import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "app.droid", category: "UpdateService")

@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/dishant0406/droid/releases/latest")
    private static let upgradeCommand = "brew update && brew upgrade --cask droidkit"

    private(set) var canCheckForUpdates = true
    private(set) var availableUpdateVersion: String?
    private(set) var latestReleasePageURL: URL?
    private(set) var isChecking = false

    private init() {
        applyFeatureFlags()
    }

    func start() {
        Task { await refreshLatestRelease(showResult: false) }
    }

    func checkForUpdates() {
        Task { await refreshLatestRelease(showResult: true) }
    }

    private func refreshLatestRelease(showResult: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            latestReleasePageURL = release.htmlURL
            if Self.isVersion(release.version, newerThan: currentVersion()) {
                availableUpdateVersion = release.version
                if showResult { showAvailableUpdate(release) }
            } else {
                availableUpdateVersion = nil
                if showResult { showNoUpdate(release) }
            }
        } catch {
            logger.warning("GitHub release check failed: \(error.localizedDescription)")
            if showResult { showUpdateError(error) }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = Self.latestReleaseURL else { throw UpdateError.invalidReleaseURL }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Droid", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.releaseFetchFailed }
        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        return GitHubRelease(
            version: Self.trimmedVersion(payload.tagName),
            htmlURL: URL(string: payload.htmlURL)
        )
    }

    private func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func showAvailableUpdate(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "Droid \(release.version) is available"
        alert.informativeText = "Droid is distributed through GitHub releases and Homebrew. To update, run:\n\n\(Self.upgradeCommand)"
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Open GitHub Release")
        alert.addButton(withTitle: "OK")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.upgradeCommand, forType: .string)
        case .alertSecondButtonReturn:
            if let url = release.htmlURL { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    private func showNoUpdate(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "Droid is up to date"
        alert.informativeText = "Installed version: \(currentVersion())\nLatest GitHub release: \(release.version)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not check for updates"
        alert.informativeText = "GitHub release check failed. You can update manually with:\n\n\(Self.upgradeCommand)\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.upgradeCommand, forType: .string)
        }
    }

    private func applyFeatureFlags() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FF_UPDATE_AVAILABLE"] != nil {
            availableUpdateVersion = "0.0.0-dev"
        }
        #endif
    }

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        normalizedVersion(current).lexicographicallyPrecedes(normalizedVersion(candidate))
    }

    private nonisolated static func normalizedVersion(_ version: String) -> [Int] {
        let parts = trimmedVersion(version).split(separator: ".").map { Int($0) ?? 0 }
        return Array((parts + [0, 0, 0]).prefix(3))
    }

    private nonisolated static func trimmedVersion(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }
}

private struct GitHubRelease {
    let version: String
    let htmlURL: URL?
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private enum UpdateError: LocalizedError {
    case invalidReleaseURL
    case releaseFetchFailed

    var errorDescription: String? {
        switch self {
        case .invalidReleaseURL:
            "The GitHub release URL is invalid."
        case .releaseFetchFailed:
            "GitHub returned an unexpected response."
        }
    }
}

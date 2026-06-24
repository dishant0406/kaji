import Foundation
import Observation
import os

private let externalIDESettingsLogger = Logger(subsystem: "app.kaji", category: "ExternalIDESettings")

@MainActor
@Observable
final class ExternalIDESettings {
    static let shared = ExternalIDESettings()

    private(set) var selectedIDEID: String?
    private(set) var customApplications: [ExternalIDECustomApplication] = []

    @ObservationIgnored private let store: CodableFileStore<ExternalIDESnapshot>
    @ObservationIgnored private var isBatchLoading = false

    init(fileURL: URL = KajiFileStorage.fileURL(filename: "external-ides.json")) {
        store = CodableFileStore(
            fileURL: fileURL,
            options: .init(prettyPrinted: true, sortedKeys: true, filePermissions: 0o600)
        )
        load()
    }

    func select(_ ideID: String?) {
        guard selectedIDEID != ideID else { return }
        selectedIDEID = ideID
        save()
    }

    @discardableResult
    func addCustomApplication(at url: URL) -> ExternalIDECustomApplication {
        let standardized = url.standardizedFileURL
        let app = ExternalIDECustomApplication(
            displayName: displayName(for: standardized),
            bundleIdentifier: bundleIdentifier(for: standardized),
            appPath: standardized.path
        )
        if let index = customApplications.firstIndex(where: { $0.id == app.id || $0.appPath == app.appPath }) {
            customApplications[index] = app
        } else {
            customApplications.append(app)
        }
        selectedIDEID = app.id
        save()
        return app
    }

    private func load() {
        do {
            guard let snapshot = try store.load() else { return }
            isBatchLoading = true
            selectedIDEID = snapshot.selectedIDEID
            customApplications = snapshot.customApplications
            isBatchLoading = false
        } catch {
            isBatchLoading = false
            externalIDESettingsLogger.error("Failed to load external IDE settings: \(error.localizedDescription)")
        }
    }

    private func save() {
        guard !isBatchLoading else { return }
        do {
            try store.save(.init(selectedIDEID: selectedIDEID, customApplications: customApplications))
        } catch {
            externalIDESettingsLogger.error("Failed to save external IDE settings: \(error.localizedDescription)")
        }
    }

    private func displayName(for url: URL) -> String {
        if let value = infoDictionary(for: url)?["CFBundleDisplayName"] as? String, !value.isEmpty {
            return value
        }
        if let value = infoDictionary(for: url)?["CFBundleName"] as? String, !value.isEmpty {
            return value
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func bundleIdentifier(for url: URL) -> String? {
        infoDictionary(for: url)?["CFBundleIdentifier"] as? String
    }

    private func infoDictionary(for url: URL) -> [String: Any]? {
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary
    }
}

private struct ExternalIDESnapshot: Codable {
    let selectedIDEID: String?
    let customApplications: [ExternalIDECustomApplication]
}

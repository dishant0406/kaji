import AppKit
import Foundation

@MainActor
@Observable
final class SpeechModelRegistryStore {
    static let shared = SpeechModelRegistryStore()

    var models: [SpeechInputModel]
    var lastError: String?
    let fileURL: URL

    @ObservationIgnored private let bundledLoader: () throws -> SpeechModelRegistryDocument
    @ObservationIgnored private let store: CodableFileStore<SpeechModelRegistryDocument>

    init(
        fileURL: URL = KajiFileStorage.fileURL(filename: "speech-models.json"),
        bundledLoader: @escaping () throws -> SpeechModelRegistryDocument = SpeechModelRegistryResources.loadBundled
    ) {
        self.fileURL = fileURL
        self.bundledLoader = bundledLoader
        store = CodableFileStore(fileURL: fileURL, options: .prettySorted)
        let loaded = Self.load(fileURL: fileURL, store: store, bundledLoader: bundledLoader)
        models = loaded.models
        lastError = loaded.error
    }

    func reload() {
        let loaded = Self.load(fileURL: fileURL, store: store, bundledLoader: bundledLoader)
        models = loaded.models
        lastError = loaded.error
    }

    func model(for id: String) -> SpeechInputModel {
        models.first { $0.id == id } ?? models.first { $0.id == SpeechInputModel.defaultID } ?? models[0]
    }

    func openRegistryFile() {
        ensureEditableFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func ensureEditableFileExists() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let loaded = Self.load(fileURL: fileURL, store: store, bundledLoader: bundledLoader)
        models = loaded.models
        lastError = loaded.error
    }

    private static func load(
        fileURL: URL,
        store: CodableFileStore<SpeechModelRegistryDocument>,
        bundledLoader: () throws -> SpeechModelRegistryDocument
    ) -> (models: [SpeechInputModel], error: String?) {
        do {
            let bundled = try bundledLoader()
            try SpeechModelRegistryValidator.validate(bundled)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try store.save(bundled)
                return (bundled.models, nil)
            }
            guard let document = try store.load() else { return (bundled.models, nil) }
            try SpeechModelRegistryValidator.validate(document)
            let migrated = SpeechModelRegistryMigration.migrated(user: document, bundled: bundled)
            if migrated != document { try store.save(migrated) }
            return (migrated.models, nil)
        } catch {
            DebugFileLog.logError("SpeechInput", error, context: "model registry load failed")
            let fallback = (try? bundledLoader().models) ?? []
            return (fallback.isEmpty ? SpeechModelRegistryResources.fallbackModels : fallback, error.localizedDescription)
        }
    }
}

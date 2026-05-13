import Foundation
import os

private let languagePackCatalogLogger = Logger(subsystem: "app.kaji", category: "LanguagePackCatalog")

struct LanguagePackCatalogEntry: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let extensions: [String]
    let filenames: [String]
    let manifestPath: String
    let sha256: String?
    let version: String
}

struct LanguagePackCatalogPayload: Codable {
    let schemaVersion: Int
    let packs: [LanguagePackCatalogEntry]
}

enum LanguagePackCatalog {
    static func allEntries() -> [LanguagePackCatalogEntry] {
        loadEntries()
    }

    @MainActor
    static func availableEntry(forFile filePath: String) -> LanguagePackCatalogEntry? {
        let installed = LanguageRegistry.shared.definition(forFile: filePath)
        guard installed == nil else { return nil }
        let entries = loadEntries()
        let url = URL(fileURLWithPath: filePath)
        let filename = url.lastPathComponent.lowercased()
        if let entry = entries.first(where: { $0.filenames.map { $0.lowercased() }.contains(filename) }) {
            return entry
        }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return entries.first { $0.extensions.map { $0.lowercased() }.contains(ext) }
    }

    static func manifestURL(for entry: LanguagePackCatalogEntry) -> URL? {
        catalogRootURL()?.appendingPathComponent(entry.manifestPath)
    }

    private static func loadEntries() -> [LanguagePackCatalogEntry] {
        guard let url = catalogRootURL()?.appendingPathComponent("registry.json") else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LanguagePackCatalogPayload.self, from: data).packs
        } catch {
            languagePackCatalogLogger.error("Failed to load language pack catalog: \(error.localizedDescription)")
            return []
        }
    }

    private static func catalogRootURL() -> URL? {
        let candidates: [URL?] = [
            Bundle.appResources.url(forResource: "LanguagePackRegistry", withExtension: nil),
            Bundle.module.url(forResource: "LanguagePackRegistry", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent("Kaji_Kaji.bundle/LanguagePackRegistry", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("LanguagePackRegistry", isDirectory: true),
        ]
        return candidates.compactMap(\.self).first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}

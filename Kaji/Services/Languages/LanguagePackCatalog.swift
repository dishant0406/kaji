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
        catalogIndex.entries
    }

    @MainActor
    static func availableEntry(forFile filePath: String) -> LanguagePackCatalogEntry? {
        let installed = LanguageRegistry.shared.definition(forFile: filePath)
        guard installed == nil else { return nil }
        return catalogIndex.entry(forFile: filePath)
    }

    static func manifestURL(for entry: LanguagePackCatalogEntry) -> URL? {
        catalogRootURL.appendingPathComponent(entry.manifestPath)
    }

    private static let catalogRootURL: URL = findCatalogRootURL()
    private static let catalogIndex = LanguagePackCatalogIndex(entries: loadEntries())

    private static func loadEntries() -> [LanguagePackCatalogEntry] {
        let url = catalogRootURL.appendingPathComponent("registry.json")
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LanguagePackCatalogPayload.self, from: data).packs
        } catch {
            languagePackCatalogLogger.error("Failed to load language pack catalog: \(error.localizedDescription)")
            return []
        }
    }

    private static func findCatalogRootURL() -> URL {
        let candidates: [URL?] = [
            Bundle.appResources.url(forResource: "LanguagePackRegistry", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent("Kaji_Kaji.bundle/LanguagePackRegistry", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("LanguagePackRegistry", isDirectory: true),
        ]
        return candidates.compactMap(\.self).first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        } ?? URL(fileURLWithPath: "/__missing_language_pack_registry__", isDirectory: true)
    }
}

struct LanguagePackCatalogIndex {
    let entries: [LanguagePackCatalogEntry]
    private let entriesByFilename: [String: LanguagePackCatalogEntry]
    private let entriesByExtension: [String: LanguagePackCatalogEntry]

    init(entries: [LanguagePackCatalogEntry]) {
        self.entries = entries
        var filenames: [String: LanguagePackCatalogEntry] = [:]
        var extensions: [String: LanguagePackCatalogEntry] = [:]
        for entry in entries {
            for filename in entry.filenames {
                filenames[filename.lowercased(), default: entry] = filenames[filename.lowercased()] ?? entry
            }
            for fileExtension in entry.extensions {
                extensions[fileExtension.lowercased(), default: entry] = extensions[fileExtension.lowercased()] ?? entry
            }
        }
        entriesByFilename = filenames
        entriesByExtension = extensions
    }

    func entry(forFile filePath: String) -> LanguagePackCatalogEntry? {
        let url = URL(fileURLWithPath: filePath)
        let filename = url.lastPathComponent.lowercased()
        if let entry = entriesByFilename[filename] {
            return entry
        }
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return nil }
        return entriesByExtension[fileExtension]
    }
}

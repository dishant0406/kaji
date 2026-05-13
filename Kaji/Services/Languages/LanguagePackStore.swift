import Foundation
import os

private let languagePackLogger = Logger(subsystem: "app.kaji", category: "LanguagePackStore")

enum LanguagePackStore {
    static func loadBundledDefinitions() -> [LanguageDefinition] {
        guard let directory = bundledLanguagePacksURL() else { return [] }
        return loadDefinitions(from: directory, source: .bundled)
    }

    static func loadUserDefinitions() -> [LanguageDefinition] {
        let directory = userLanguagePacksURL()
        return loadDefinitions(from: directory, source: .user)
    }

    static func userLanguagePacksURL() -> URL {
        let url = KajiFileStorage.appSupportDirectory()
            .appendingPathComponent("language-packs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private static func bundledLanguagePacksURL() -> URL? {
        let candidates: [URL?] = [
            Bundle.appResources.url(forResource: "LanguagePacks", withExtension: nil),
            Bundle.module.url(forResource: "LanguagePacks", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent("Kaji_Kaji.bundle/LanguagePacks", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("LanguagePacks", isDirectory: true),
        ]
        return candidates.compactMap(\.self).first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func loadDefinitions(from directory: URL, source: LanguageDefinition.Source) -> [LanguageDefinition] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var definitions: [LanguageDefinition] = []
        for case let url as URL in enumerator where url.lastPathComponent == "manifest.json" {
            do {
                let data = try Data(contentsOf: url)
                let manifest = try LanguagePackValidator.validateManifestData(data, expectedSHA256: nil)
                let definition = manifest.definition(source: source, rootURL: url.deletingLastPathComponent())
                let missing = LanguagePackAssetValidator.validateAssets(for: definition)
                if !missing.isEmpty {
                    languagePackLogger.warning("Language pack \(definition.id) has missing syntax assets: \(missing.joined(separator: ", "))")
                }
                definitions.append(definition)
            } catch {
                languagePackLogger.error("Failed to load language pack at \(url.path): \(error.localizedDescription)")
            }
        }
        return definitions
    }
}

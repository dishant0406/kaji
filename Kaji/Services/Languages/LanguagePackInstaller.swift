import Foundation
import os

private let languagePackInstallerLogger = Logger(subsystem: "app.kaji", category: "LanguagePackInstaller")

enum LanguagePackInstaller {
    @MainActor
    static func install(_ entry: LanguagePackCatalogEntry) -> Result<LanguageDefinition, Error> {
        guard let sourceURL = LanguagePackCatalog.manifestURL(for: entry) else {
            return .failure(InstallError.missingManifest)
        }
        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let targetDirectory = LanguagePackStore.userLanguagePacksURL()
            .appendingPathComponent(entry.id, isDirectory: true)
        let targetURL = targetDirectory.appendingPathComponent("manifest.json")
        do {
            let data = try Data(contentsOf: sourceURL)
            let manifest = try LanguagePackValidator.validateManifestData(data, expectedSHA256: entry.sha256)
            try FileManager.default.createDirectory(
                at: targetDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try copyAssets(for: manifest, from: sourceDirectory, to: targetDirectory)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try data.write(to: targetURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
            LanguageRegistry.shared.reload()
            return .success(manifest.definition(source: .user, rootURL: targetDirectory))
        } catch {
            languagePackInstallerLogger.error("Failed to install language pack \(entry.id): \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private static func copyAssets(for manifest: LanguagePackManifest, from sourceDirectory: URL, to targetDirectory: URL) throws {
        let paths = assetPaths(for: manifest)
        for path in paths {
            let sourceURL = sourceDirectory.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            let targetURL = targetDirectory.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        }
    }

    private static func assetPaths(for manifest: LanguagePackManifest) -> [String] {
        guard let syntax = manifest.syntax else { return [] }
        var paths: [String] = []
        if let parser = syntax.treeSitter?.parser.artifact {
            paths.append(parser)
        }
        if let queries = syntax.treeSitter?.queries {
            paths.append(contentsOf: [queries.highlights, queries.injections, queries.locals, queries.folds].compactMap(\.self))
        }
        if let grammar = syntax.textMate?.grammar {
            paths.append(grammar)
        }
        return Array(Set(paths))
    }

    enum InstallError: LocalizedError {
        case missingManifest

        var errorDescription: String? {
            switch self {
            case .missingManifest:
                "The language pack manifest could not be found."
            }
        }
    }
}
